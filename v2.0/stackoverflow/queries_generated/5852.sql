-- {"query": "5852.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 975} 
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.ViewCount * 0.6 + p.Score * 1.4 + COALESCE(p.AnswerCount,0) * 2 + COALESCE(p.CommentCount,0) * 0.5
        DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    unnest(string_to_array(
             substr(p.Tags, 2, length(p.Tags)-2),
             '><')) AS TagName,
    SUM(p.ViewCount) AS TagViews,
    SUM(p.Score) AS TagScore
  FROM RecentPopularQuestions rp
  CROSS JOIN LATERAL unnest(string_to_array(
             substr(rp.Tags, 2, length(rp.Tags)-2),
             '><')) AS TagName
  GROUP BY TagName
),
CorrelatedUserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.AccountId,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.WebsiteUrl,
    u.AboutMe,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    MAX(b.Date) AS MostRecentBadge
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.AccountId, u.Location, u.Views, u.UpVotes, u.DownVotes,
    u.ProfileImageUrl, u.EmailHash, u.WebsiteUrl, u.AboutMe
),
ActivitySummary AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastActivityDate,
    ARRAY_AGG(DISTINCT v.VoteTypeId) AS VoteTypesOnPost,
    COUNT(DISTINCT c.Id) AS CommentCountOnPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.LastActivityDate
),
Final AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    cu.UserId AS OwnerUserId,
    cu.DisplayName AS OwnerDisplayName,
    cu.Reputation,
    cu.MostRecentBadge,
    asy.LastActivityDate,
    asy.VoteTypesOnPost,
    asy.CommentCountOnPost
  FROM RecentPopularQuestions rp
  LEFT JOIN CorrelatedUserStats cu ON cu.UserId = rp.OwnerUserId
  LEFT JOIN ActivitySummary asy ON asy.PostId = rp.PostId
  WHERE rp.rn <= 3 -- top 3 by per-user popularity
)
SELECT
  json_build_object(
    'summary', json_build_object(
      'generated_at', now(),
      'description', 'Benchmark snapshot: top few questions per user with rich attributes'
    ),
    'data', json_agg(
      json_build_object(
        'post_id', PostId,
        'title', Title,
        'tags', Tags,
        'creation_date', CreationDate,
        'views', ViewCount,
        'score', Score,
        'answers', COALESCE(AnswerCount, 0),
        'comments', COALESCE(CommentCount, 0),
        'owner', json_build_object(
          'user_id', OwnerUserId,
          'display_name', OwnerDisplayName,
          'reputation', Reputation,
          'most_recent_badge', MostRecentBadge
        ),
        'last_activity', asy_LastActivityDate,
        'vote_kinds', VoteTypesOnPost,
        'comments_on_post', CommentCountOnPost,
        'top_tags', (SELECT json_agg(TagName) FROM TopTags t WHERE t.TagName IS NOT NULL)
      )
    )
  ) AS benchmark_result
FROM Final;