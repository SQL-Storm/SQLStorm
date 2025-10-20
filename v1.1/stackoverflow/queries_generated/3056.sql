-- {"query": "3056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1350} 
WITH UserReputationStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           CASE WHEN u.Reputation IS NULL THEN 0 ELSE u.Reputation END AS SafeReputation,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate DESC) AS RecentActivityRank
    FROM Users u
),
PostAnswerCounts AS (
    SELECT p.OwnerUserId,
           COUNT(a.Id) AS TotalAnswers
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
BadgesByType AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) AS VoteCountLast30Days
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY v.UserId
),
PostTypeDistribution AS (
    SELECT pt.Id AS PostTypeId,
           pt.Name AS PostTypeName,
           COUNT(p.Id) AS PostCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY pt.Id, pt.Name
),
TaggedQuestions AS (
    SELECT p.Tags,
           REGEXP_SPLIT_TO_ARRAY(TRIM(BOTH '{}' FROM p.Tags), '<>') AS TagList
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
MostCommonTags AS (
    SELECT tag, COUNT(*) AS TagFrequency
    FROM (
        SELECT unnest(TagList) AS tag
        FROM TaggedQuestions
    ) sub
    GROUP BY tag
    ORDER BY TagFrequency DESC
    LIMIT 10
),
PostsWithComments AS (
    SELECT p.Id AS PostId,
           COUNT(c.Id) AS CommentCount,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
ActiveUserPosts AS (
    SELECT u.Id AS UserId,
           COUNT(DISTINCT p.Id) AS ActivePostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
    GROUP BY u.Id
),
PostHistorySummary AS (
    SELECT ph.PostId,
           COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12)) AS TotalEdits,
           MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS LastEditDate,
           STRING_AGG(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS TEXT) END, ', ') AS CloseReasons
    FROM PostHistory ph
    GROUP BY ph.PostId
), 
LinkedPosts AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
FinalAggregated AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        br.GoldBadges,
        br.SilverBadges,
        br.BronzeBadges,
        COALESCE(ra.TotalAnswers, 0) AS AnswerCount,
        ri.VoteCountLast30Days,
        coalesce(pt.PostTypeName, 'Unknown') AS PrimaryPostType,
        COUNT(p.Id) AS TotalPosts,
        MAX(p.CreationDate) AS LastPostDate,
        cs.CommentCount,
        COALESCE(au.ActivePostCount, 0) AS ActivePosts,
        hs.TotalEdits,
        hs.LastEditDate,
        hs.CloseReasons,
        STRING_AGG(DISTINCT lt.Name, ', ') AS RelatedLinkTypes,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinkedPosts
    FROM Users u
    LEFT JOIN BadgesByType br ON u.Id = br.UserId
    LEFT JOIN PostAnswerCounts ra ON u.Id = ra.OwnerUserId
    LEFT JOIN RecentVotes ri ON u.Id = ri.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts p2 ON u.Id = p2.OwnerUserId
                       AND p2.PostTypeId = 1
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Posts p3 ON p3.OwnerUserId = u.Id
    LEFT JOIN Posts p4 ON p4.OwnerUserId = u.Id
    LEFT JOIN Posts p5 ON p5.OwnerUserId = u.Id
    LEFT JOIN Posts p6 ON p6.OwnerUserId = u.Id
    LEFT JOIN Posts p7 ON p7.OwnerUserId = u.Id
    LEFT JOIN Posts p8 ON p8.OwnerUserId = u.Id
    LEFT JOIN PostHistory hs ON hs.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN PostTypeDistribution pt ON p.PostTypeId = pt.PostTypeId
    LEFT JOIN ActiveUserPosts au ON u.Id = au.UserId
    LEFT JOIN PostHistorySummary hs ON p.Id = hs.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation, br.GoldBadges, br.SilverBadges, br.BronzeBadges, ra.TotalAnswers, ri.VoteCountLast30Days, p.PostTypeId, p.PostTypeName, c.CommentCount, au.ActivePostCount, hs.TotalEdits, hs.LastEditDate, hs.CloseReasons
)
SELECT * FROM FinalAggregated
WHERE Reputation > 1000 OR AnswerCount > 50
ORDER BY Reputation DESC, AnswerCount DESC
LIMIT 100;