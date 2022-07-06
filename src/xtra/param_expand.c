#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <ctype.h>
#include <string.h>
#include <errno.h>
#include <assert.h>
#include <sys/mman.h>

/* Maximum buffer size - default, 1MB */
#define MAX_BUFFER_SIZE	(1024*1024)

struct envitem {
	const char *key;
	const char *val;
	char *toexpand; /* "${key}" */
	unsigned int toexpand_len;
	unsigned int val_len;
	struct envitem *next;
};

static struct envitem *list;
static const char empty[] = { '\0' };

struct envitem *envitem_add(const char *key)
{
	struct envitem *ret = malloc(sizeof(*ret));
	if (!ret)
		return NULL;
	ret->key = key;
	ret->val = getenv(ret->key);
	if (!ret->val)
		ret->val = empty;
	ret->toexpand = malloc(strlen(key) + 4);
	if (!ret->toexpand) {
		free(ret);
		return NULL;
	}
	sprintf(ret->toexpand, "${%s}", key);
	ret->toexpand_len = strlen(ret->toexpand);
	ret->val_len = strlen(ret->val);
	ret->next = list;
	list = ret;
	return ret;
}

static int is_valid_key(const char *s, unsigned int len)
{
	if (!len)
		return 0;
	while (len--) {
		if (!isalnum(*s) && (*s != '_'))
			return 0;
		s++;
	}
	return 1;
}

struct buffer {
	char *ptr;
	unsigned long sz;
	unsigned long used;
};

static int buffer_new(struct buffer *buf, unsigned long sz)
{
	buf->sz = MAX_BUFFER_SIZE;
	buf->used = 0;
	buf->ptr = mmap(NULL, buf->sz, PROT_READ | PROT_WRITE,
			MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	if (buf->ptr == MAP_FAILED) {
		fprintf(stderr, "ERROR: failed to create buf (sz=%lu)\n",
			buf->sz);
		return -ENOMEM;
	}
	return 0;
}

static int buffer_read_file(struct buffer *buf, int fd)
{
	while (buf->used < buf->sz) {
		ssize_t cnt = read(fd,
				   buf->ptr + buf->used,
				   buf->sz - buf->used);
		if (cnt < 0) {
			fprintf(stderr, "ERROR, file read failed at %lu bytes: %s\n",
				buf->used, strerror(errno));
			return -1;
		}
		buf->used += cnt;
		if (buf->used >= buf->sz) {
			fprintf(stderr, "ERROR, file goes beyond %lu bytes\n",
				buf->used);
			return -1;
		}
		if (!cnt) {
			/* Make sure the buffer is NUL-terminated */
			if (buf->used == buf->sz) {
				fprintf(stderr, "ERROR, buffer too full\n");
				return -1;
			}
			buf->ptr[buf->used] = '\0';
			return 0;
		}
	}
	return -ENOMEM;
}

static int buffer_write_file(const struct buffer *buf, int fd)
{
	unsigned long done = 0;
	while (done < buf->used) {
		ssize_t cnt = write(fd,
				    buf->ptr + done,
				    buf->used - done);
		if (cnt <= 0) {
			fprintf(stderr, "ERROR, file write failed at %lu bytes: %s\n",
				done, strerror(errno));
			return -1;
		}
		done += cnt;
		assert(done <= buf->used);
	}
	return 0;
}

static int buffer_is_string(const struct buffer *buf)
{
	size_t len = strnlen(buf->ptr, buf->sz);
	if (buf->used >= buf->sz) {
		fprintf(stderr, "ERROR, buffer to full to hold terminator");
		return 0;
	}
	if (len < buf->used) {
		fprintf(stderr, "ERROR: buffer contains premature NUL");
		return 0;
	}
	if (len > buf->used) {
		fprintf(stderr, "ERROR: no NUL-termination found");
		return 0;
	}
	return 1;
}

static int buffer_expand_envitem(struct buffer *buf,
				 const struct envitem *env)
{
	const char *x;
	unsigned long start = 0;
	while ((start < buf->used) && (x = strstr(buf->ptr + start,
						  env->toexpand))) {
		unsigned long offset, escapes, escapecursor;
		offset = ((unsigned long)x - (unsigned long)buf->ptr);
		/* Search backward for "\" escapes */
		escapes = 0;
		escapecursor = offset;
		while ((escapecursor-- > start) &&
				(buf->ptr[escapecursor] == '\\'))
			escapes++;
		if ((escapes & 1)) {
			/* Odd number of escapes, bypass this match */
			start = offset + env->toexpand_len;
			continue;
		}
		if (env->toexpand_len < env->val_len) {
			memmove(buf->ptr + offset + env->val_len,
				buf->ptr + offset + env->toexpand_len,
				buf->used - (offset + env->toexpand_len));
			buf->used += env->val_len - env->toexpand_len;
		} else if (env->toexpand_len > env->val_len) {
			memmove(buf->ptr + offset + env->val_len,
				buf->ptr + offset + env->toexpand_len,
				buf->used - (offset + env->toexpand_len));
			buf->used -= env->toexpand_len - env->val_len;
		}
		if (buf->used >= buf->sz) {
			fprintf(stderr, "ERROR, buffer overflowing\n");
			return -ENOMEM;
		}
		buf->ptr[buf->used] = '\0';
		memcpy(buf->ptr + offset, env->val, env->val_len);
		start = offset + env->val_len;
	}
	return 0;
}

#define SHIFT() ({++argv; --argc;})

int main(int argc, char **argv)
{
	struct buffer buf;
	struct envitem *envitem;
	int ret;
	while (SHIFT()) {
		if (!is_valid_key(*argv, strlen(*argv))) {
			fprintf(stderr, "WARN: skipping invalid env key '%s'\n",
				*argv);
		} else if (!(envitem = envitem_add(*argv))) {
			fprintf(stderr, "ERROR: failed to add env key '%s'\n",
				*argv);
			return -1;
		}
	}
	if ((ret = buffer_new(&buf, MAX_BUFFER_SIZE)))
		return ret;
	if ((ret = buffer_read_file(&buf, STDIN_FILENO)))
		return ret;
	if (!buffer_is_string(&buf))
		return ret;
	for(envitem = list; envitem; envitem = envitem->next) {
		if ((ret = buffer_expand_envitem(&buf, envitem)))
			return ret;
	}
	if ((ret = buffer_write_file(&buf, STDOUT_FILENO)))
		return ret;
	return 0;
}
