-- {"query": "5293.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1104} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopCommenters AS (
  SELECT
    c.PostId,
    c.UserId AS CommentUserId,
    c.Score AS CommentScore,
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate ASC) AS rn
  FROM Comments c
  WHERE c.UserId IS NOT NULL
),
QuestionTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.Location,
    u.ProfileImageUrl
  FROM Users u
),
Composite AS (
  SELECT
    RAP.PostId,
    RAP.Title,
    RAP.Body,
    RAP.Tags,
    RAP.CreationDate,
    RAP.ViewCount,
    RAP.Score,
    RAP.OwnerUserId,
    RAP.LastActivityDate,
    RAP.CommentCount,
    RAP.AnswerCount,
    RAP.PostTypeId,
    MAX(CASE WHEN TC.rn = 1 THEN TC.CommentScore ELSE NULL END) AS TopCommentScore,
    MAX(CASE WHEN TC.rn = 1 THEN TC.CommentUserId ELSE NULL END) AS TopCommentUserId,
    MAX(CASE WHEN TA.TagName IS NOT NULL THEN TA.TagName ELSE NULL END) AS PrimaryTag
  FROM RecentActivePosts RAP
  LEFT JOIN TopCommenters TC
    ON RAP.PostId = TC.PostId
  LEFT JOIN (
    SELECT DISTINCT ON (PostId) PostId, TagName
    FROM (SELECT * FROM QuestionTags) qt
  ) TA
    ON RAP.PostId = TA.PostId
  GROUP BY
    RAP.PostId, RAP.Title, RAP.Body, RAP.Tags, RAP.CreationDate, RAP.ViewCount, RAP.Score,
    RAP.OwnerUserId, RAP.LastActivityDate, RAP.CommentCount, RAP.AnswerCount, RAP.PostTypeId
),
Enhanced AS (
  SELECT
    C.PostId,
    C.Title,
    C.Body,
    C.Tags,
    C.CreationDate,
    C.ViewCount,
    C.Score,
    C.OwnerUserId,
    C.LastActivityDate,
    C.CommentCount,
    C.AnswerCount,
    C.PostTypeId,
    C.TopCommentScore,
    C.TopCommentUserId,
    C.PrimaryTag,
    UA.DisplayName AS OwnerDisplayName,
    UA.Reputation,
    UA.Location,
    UA.ProfileImageUrl,
    VA.LastAccessDate
  FROM Composite C
  LEFT JOIN UserActivity UA
    ON C.OwnerUserId = UA.UserId
  LEFT JOIN (
    SELECT UserId, MAX(LastAccessDate) AS LastAccessDate FROM Users GROUP BY UserId
  ) VA
    ON C.OwnerUserId = VA.UserId
),
Windowed AS (
  SELECT
    E.*,
    ROW_NUMBER() OVER (
      ORDER BY E.Score DESC,
               E.LastActivityDate DESC,
               COALESCE(E.TopCommentScore, 0) DESC,
               COALESCE(E.Reputation, 0) DESC
    ) AS rn
  FROM Enhanced E
),
Final AS (
  SELECT
    w.PostId,
    w.Title,
    w.Body,
    w.Tags,
    w.CreationDate,
    w.ViewCount,
    w.Score,
    w.OwnerUserId,
    w.LastActivityDate,
    w.CommentCount,
    w.AnswerCount,
    w.PostTypeId,
    w.TopCommentScore,
    w.TopCommentUserId,
    w.PrimaryTag,
    w.OwnerDisplayName,
    w.Reputation,
    w.Location,
    w.ProfileImageUrl,
    w.LastAccessDate
  FROM Windowed w
  WHERE w.rn <= 50
)
SELECT
  JSON_BUILD_OBJECT(
    'top_posts', JSON_AGG(
      JSON_BUILD_OBJECT(
        'post_id', PostId,
        'title', Title,
        'tags', Tags,
        'creation_date', CreationDate,
        'score', Score,
        'view_count', ViewCount,
        'owner', JSON_BUILD_OBJECT(
          'user_id', OwnerUserId,
          'display_name', OwnerDisplayName,
          'reputation', Reputation,
          'location', Location
        ),
        'last_activity', LastActivityDate,
        'comment_count', CommentCount,
        'answer_count', AnswerCount,
        'primary_tag', PrimaryTag,
        'top_comment', COALESCE(TopCommentScore, 0)
      )
    )
  ) AS benchmark_result
FROM Final;