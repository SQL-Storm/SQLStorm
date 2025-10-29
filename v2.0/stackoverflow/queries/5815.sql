WITH
RecentActivePosts AS (
  SELECT p.Id,
         p.PostTypeId,
         p.Title,
         p.Tags,
         p.CreationDate,
         p.LastActivityDate,
         p.OwnerUserId,
         p.ViewCount,
         p.Score,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
TagStats AS (
  SELECT t.TagName,
         COUNT(*) AS TagPostCount,
         AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
         SUM(p.ViewCount) AS TotalViews
  FROM Tags t
  JOIN Posts p ON p.Id = t.Id OR p.Id = t.WikiPostId
  GROUP BY t.TagName
),
TopContributors AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.Views,
         u.UpVotes,
         u.DownVotes,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
UserBadges AS (
  SELECT b.UserId,
         COUNT(*) AS BadgeCount,
         string_agg(b.Name, ',' ORDER BY b.Name) AS BadgeNames
  FROM Badges b
  GROUP BY b.UserId
),
RecentVotes AS (
  SELECT v.PostId,
         v.VoteTypeId,
         v.UserId,
         v.CreationDate,
         v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7' DAY)
),
OpenCloseActivity AS (
  SELECT ph.PostId,
         ph.PostHistoryTypeId,
         ph.Comment,
         ph.CreationDate,
         ph.UserId,
         ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,11,16,50)
)
SELECT
  rp.Id AS PostId,
  rp.PostTypeId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.OwnerUserId,
  ru.DisplayName AS OwnerDisplayName,
  ru.Reputation AS OwnerReputation,
  ru.Views AS OwnerViews,
  ru.UpVotes AS OwnerUpVotes,
  ru.DownVotes AS OwnerDownVotes,
  rp.ViewCount,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  tname.TagName AS TopTaggedName,
  ts.TagPostCount,
  ts.AvgQuestionScore,
  ts.TotalViews,
  uc.DisplayName AS TopResponder,
  uc2.DisplayName AS LastEditorName,
  ubd.BadgeNames AS BadgesEarned,
  ub.BadgeCount AS BadgeCount,
  rv.VoteTypeId AS RecentVoteType,
  rv.CreationDate AS RecentVoteDate,
  ac.Comment AS CloseComment,
  ac.CreationDate AS CloseDate
FROM RecentActivePosts rp
LEFT JOIN LATERAL (
  SELECT t.TagName
  FROM Tags t
  WHERE rp.Title ILIKE '%' || t.TagName || '%'
  FETCH FIRST 1 ROWS ONLY
) tname ON TRUE
LEFT JOIN TagStats ts ON ts.TagName = tname.TagName
LEFT JOIN Users ru ON ru.Id = rp.OwnerUserId
LEFT JOIN Users uc ON uc.Id = rp.OwnerUserId
LEFT JOIN Users uc2 ON uc2.Id = rp.OwnerUserId
LEFT JOIN UserBadges ub ON ub.UserId = rp.OwnerUserId
LEFT JOIN TopContributors tc ON tc.UserId = rp.OwnerUserId
LEFT JOIN UserBadges ubd ON ubd.UserId = rp.OwnerUserId
LEFT JOIN RecentVotes rv ON rv.PostId = rp.Id
LEFT JOIN OpenCloseActivity ac ON ac.PostId = rp.Id
GROUP BY
  rp.Id,
  rp.PostTypeId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.OwnerUserId,
  ru.DisplayName,
  ru.Reputation,
  ru.Views,
  ru.UpVotes,
  ru.DownVotes,
  rp.ViewCount,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  tname.TagName,
  ts.TagPostCount,
  ts.AvgQuestionScore,
  ts.TotalViews,
  uc.DisplayName,
  uc2.DisplayName,
  ubd.BadgeNames,
  ub.BadgeCount,
  rv.VoteTypeId,
  rv.CreationDate,
  ac.Comment,
  ac.CreationDate
ORDER BY rp.LastActivityDate DESC
FETCH FIRST 100 ROWS ONLY;