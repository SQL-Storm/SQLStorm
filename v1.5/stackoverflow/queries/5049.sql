-- {"query": "5049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1243} 
WITH RecentActiveUsers AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate,
           COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC, u.Reputation DESC) AS rn
      FROM Users u
      LEFT JOIN Badges b ON b.UserId = u.Id
     WHERE u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
     GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), TopActiveUsers AS (
    SELECT *
      FROM RecentActiveUsers
     WHERE rn <= 50
), PostCounts AS (
    SELECT p.OwnerUserId,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
           COUNT(DISTINCT CASE WHEN p.PostTypeId IN (3,4,5,6,7,8) THEN p.Id END) AS OtherPosts,
           MIN(p.CreationDate) AS FirstPostDate,
           MAX(p.LastActivityDate) AS LastPostActivity
      FROM Posts p
     WHERE p.OwnerUserId IS NOT NULL
     GROUP BY p.OwnerUserId
), UserVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesGiven,
           SUM(COALESCE(v.BountyAmount,0)) AS BountyGiven
      FROM Votes v
     WHERE v.UserId IS NOT NULL
     GROUP BY v.UserId
), ReceivedVotes AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesReceived,
           SUM(COALESCE(v.BountyAmount,0)) AS BountyReceived
      FROM Votes v
INNER JOIN Posts p ON v.PostId = p.Id AND p.OwnerUserId IS NOT NULL
     GROUP BY p.OwnerUserId
), InfluentialTags AS (
    SELECT p.OwnerUserId,
           LOWER(trim(both '<>' FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))) AS TagName
      FROM Posts p
     WHERE p.OwnerUserId IS NOT NULL
       AND p.PostTypeId = 1
       AND p.Tags IS NOT NULL
), TagStats AS (
    SELECT it.OwnerUserId,
           t.TagName,
           COUNT(*) AS TagUseCount,
           RANK() OVER (PARTITION BY it.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
      FROM InfluentialTags it
INNER JOIN Tags t ON t.TagName = it.TagName
     GROUP BY it.OwnerUserId, t.TagName
), TopUserTags AS (
    SELECT OwnerUserId, TagName, TagUseCount
      FROM TagStats
     WHERE TagRank = 1
), CloseActions AS (
    SELECT ph.UserId,
           COUNT(*) FILTER(WHERE ph.PostHistoryTypeId = 10) AS PostsClosed,
           COUNT(*) FILTER(WHERE cr.Name = 'Off-topic') AS OffTopicClosed,
           COUNT(DISTINCT ph.PostId) FILTER(WHERE cr.Name = 'Duplicate') AS DistinctDuplicateClosedQuestions
      FROM PostHistory ph
LEFT JOIN CloseReasonTypes cr 
        ON cr.Id::varchar = ph.Comment
     WHERE ph.PostHistoryTypeId = 10
     GROUP BY ph.UserId
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.BadgeCount,
    u.GoldBadges,
    pc.Questions,
    pc.Answers,
    pc.OtherPosts,
    pc.FirstPostDate,
    pc.LastPostActivity,
    uv.UpvotesGiven,
    uv.DownvotesGiven,
    COALESCE(uv.FavoritesGiven, 0) AS FavoritesGiven,
    uv.BountyGiven,
    rv.UpvotesReceived,
    rv.DownvotesReceived,
    COALESCE(rv.FavoritesReceived, 0) AS FavoritesReceived,
    rv.BountyReceived,
    tut.TagName AS MostUsedTag,
    tut.TagUseCount AS MostUsedTagCount,
    ca.PostsClosed,
    ca.OffTopicClosed,
    ca.DistinctDuplicateClosedQuestions,
    CASE 
      WHEN (pc.Questions IS NULL OR pc.Questions = 0) THEN NULL
      ELSE ROUND(CAST(rv.UpvotesReceived AS NUMERIC) / NULLIF(pc.Questions,0),2)
    END AS AvgQuestionUpvotes,
    CASE
      WHEN u.BadgeCount = 0 THEN 'Newbie'
      WHEN u.GoldBadges >= 3 THEN 'Elite'
      WHEN u.GoldBadges >= 1 THEN 'Distinguished'
      ELSE 'Contributor'
    END AS UserClass
FROM TopActiveUsers u
LEFT JOIN PostCounts pc ON u.UserId = pc.OwnerUserId
LEFT JOIN UserVotes uv ON u.UserId = uv.UserId
LEFT JOIN ReceivedVotes rv ON u.UserId = rv.UserId
LEFT JOIN TopUserTags tut ON u.UserId = tut.OwnerUserId
LEFT JOIN CloseActions ca ON u.UserId = ca.UserId
ORDER BY u.Reputation DESC, u.BadgeCount DESC, u.LastAccessDate DESC;