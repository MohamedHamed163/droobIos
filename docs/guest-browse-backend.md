# Backend change — pre-login course browsing (App Store 5.1.1(v))

Apple rejected the app because free courses required an account to view. The
iOS app now has a **pre-login "Browse Courses"** flow (a guest can browse the
catalog and open a course preview without signing in; enrolling still requires
an account). For that to work, two read-only endpoints must be reachable
without a token.

Apply the patch: `git apply docs/guest-browse-backend.patch` (or just make the
two edits below), then redeploy.

## What changed (2 files)

1. **`security/SecurityConfig.java`** — permit anonymous **GET** on the catalog
   list + a single course's detail, *before* the `/v1/student/**` →
   `hasRole("STUDENT")` rule:

   ```java
   .requestMatchers(HttpMethod.GET,
           "/v1/student/courses",
           "/v1/student/courses/*")
   .permitAll()
   .requestMatchers("/v1/student/**")
   .hasRole("STUDENT")
   ```

   `/v1/student/courses/*` is **single-segment**, so nested routes
   (`…/reviews`, `…/questions`, `…/subscribe`) and every non-GET verb stay
   STUDENT-only. Only the list and the detail open up.

2. **`api/student/StudentCatalogController.java`** — `listCourses` and
   `getCourse` no longer assume a principal:

   ```java
   principal != null ? principal.getId() : null
   ```

## The one thing to verify before deploy

The controller now passes `userId = null` for anonymous callers into:

- `StudentService.listPublishedCourses(null, category, level, pageable)`
- `StudentService.getCourseDetail(null, courseId)`

These already take the `userId` only to compute the per-user **`enrolled`**
flag / progress via repository params
(`enrollmentRepository.existsByUser_IdAndCourse_Id(userId, courseId)`,
`courseRepository.findPublishedOrEnrolledById(courseId, userId)`,
`toSummary(course, userId, …)`). Passing `null` should resolve to
"not enrolled" because the JPQL binds `:userId` as a SQL parameter (`= null`
matches nothing).

**Check there is no Java-side NPE on the null path** — i.e. nothing does
`userId.equals(...)` / `userId.toString()` *before* it reaches the query. If
any of those methods dereference `userId`, guard it (`userId == null ? false :
…`). A guest must get the published catalog with every course marked
not-enrolled, and a published course's detail with `enrolled=false`,
no progress, no pending-request state.

## Test (no token = guest)

```bash
# Catalog list — must return 200 with the published courses
curl -i https://api.droob-sa.net/v1/student/courses

# Course detail — must return 200 with "enrolled": false
curl -i https://api.droob-sa.net/v1/student/courses/<COURSE_ID>

# Still protected (must be 401/403 without a token)
curl -i https://api.droob-sa.net/v1/student/enrollments
curl -i -X POST https://api.droob-sa.net/v1/student/courses/<COURSE_ID>/subscribe
```

A signed-in student keeps getting the personalised view (correct `enrolled`
flags) because the token is still sent and honoured on these endpoints.
