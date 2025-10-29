-- {"query": "5673.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1085} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COALESCE(u.LastAccessDate, u.CreationDate) DESC) AS rn
  FROM Users u
),
tag_popularity AS (
  SELECT
    t.TagName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS PostScoreSum,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(b.Id) AS BadgeCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' OR p.Tags LIKE '%<' || t.TagName || '>%'
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.Name = t.TagName
  GROUP BY t.TagName
),
complex_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    LAST_VALUE(p.LastEditDate) OVER (PARTITION BY p.Id ORDER BY p.LastEditDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS LastEditDateWindow,
    COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountWindow
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
open_close_activity AS (
  SELECT
    co.PostId,
    co.LastActivityDate,
    co.ClosedDate,
    co.CommunityOwnedDate,
    SUM(CASE WHEN pv.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM complex_posts co
  LEFT JOIN Votes pv ON pv.PostId = co.PostId
  GROUP BY co.PostId, co.LastActivityDate, co.ClosedDate, co.CommunityOwnedDate
),
cte_experimental AS (
  SELECT
    rp.UserId,
    rp.DisplayName,
    rp.Reputation,
    rp.CreationDate,
    rp.LastAccessDate,
    rp.Views,
    rp.UpVotes,
    rp.DownVotes,
    rp.AccountId,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagSet,
    SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionScore,
    SUM(b.Class) AS BadgeClasses
  FROM recent_user_activity rp
  LEFT JOIN Posts p ON p.OwnerUserId = rp.UserId
  LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Badges b ON b.UserId = rp.UserId
  WHERE rp.rn = 1
  GROUP BY
    rp.UserId, rp.DisplayName, rp.Reputation, rp.CreationDate, rp.LastAccessDate, rp.Views, rp.UpVotes, rp.DownVotes, rp.AccountId
)
SELECT
  cu.UserId,
  cu.DisplayName,
  cu.Reputation,
  cu.CreationDate,
  cu.LastAccessDate,
  cu.Views,
  cu.UpVotes,
  cu.DownVotes,
  cu.AccountId,
  cu.TagSet,
  cu.TotalQuestionScore,
  cu.BadgeClasses,
  jsonb_build_object(
    'RecentActivity', to_char(aro.LastActivityDate, 'YYYY-MM-DD HH24:MI:SS'),
    'OpenClosed', (
      SELECT jsonb_agg(jsonb_build_object(
        'PostId', e.PostId,
        'LastActivityDate', e.LastActivityDate,
        'ClosedDate', e.ClosedDate,
        'CommunityOwnedDate', e.CommunityOwnedDate,
        'CloseVotes', e.CloseVotes
      ))
      FROM open_close_activity e
      WHERE e.PostId = aro.PostId
    )
  ) AS ActivitySummary
FROM cte_experimental cu
JOIN recent_user_activity aru ON aru.Id = cu.UserId
LEFT JOIN complex_posts aro ON aro.OwnerUserId = cu.UserId
ORDER BY cu.Reputation DESC, cu.LastAccessDate DESC
LIMIT 100;