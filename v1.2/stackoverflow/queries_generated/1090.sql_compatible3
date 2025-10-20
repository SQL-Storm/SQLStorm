WITH UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY) THEN 1 ELSE 0 END), 0) AS BadgesLastYear,
        COALESCE(MAX(b.Date), DATE '1970-01-01') AS LastBadgeDate
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostInteractions AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(vt_up.VoteCount, 0) AS UpVotesCount,
        COALESCE(vt_down.VoteCount, 0) AS DownVotesCount,
        COALESCE(comm.CommentCount, 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_best_posts
    FROM
        Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) vt_up ON p.Id = vt_up.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount
        FROM Votes
        WHERE VoteTypeId = 3
        GROUP BY PostId
    ) vt_down ON p.Id = vt_down.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId
    ) comm ON p.Id = comm.PostId
    WHERE p.PostTypeId IN (1, 2)
),
TopPostsWithRanking AS (
    SELECT 
        pi.PostId,
        pi.PostTypeId,
        pi.OwnerUserId,
        pi.Title,
        pi.CreationDate,
        pi.Score,
        pi.ViewCount,
        pi.Tags,
        pi.UpVotesCount,
        pi.DownVotesCount,
        pi.CommentCount,
        pi.rn_best_posts,
        u.DisplayName AS OwnerName,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.BadgesLastYear,
        ub.LastBadgeDate,
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = pi.OwnerUserId AND p2.Score > pi.Score) + 1 AS ScoreRank,
        (SELECT COUNT(*) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = pi.OwnerUserId AND p3.ViewCount > pi.ViewCount) + 1 AS ViewRank
    FROM 
        PostInteractions pi
    LEFT JOIN 
        Users u ON pi.OwnerUserId = u.Id
    LEFT JOIN
        UserBadgeSummary ub ON ub.UserId = pi.OwnerUserId
    WHERE pi.rn_best_posts <= 5
),
ClosedDuplicatePosts AS (
    SELECT DISTINCT
        ph.PostId,
        ph.Comment AS CloseReasonId,
        crt.Name AS CloseReasonName,
        pl_related.RelatedPostId AS DuplicateOfPostId,
        rp.Title AS DuplicateOfTitle
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    LEFT JOIN PostLinks pl_related ON ph.PostId = pl_related.PostId AND pl_related.LinkTypeId = 3
    LEFT JOIN Posts rp ON pl_related.RelatedPostId = rp.Id
    WHERE ph.PostHistoryTypeId = 10
      AND CAST(ph.Comment AS SMALLINT) IN (101)
),
TagUsageAndScore AS (
    SELECT
        t AS Tag,
        p.Score,
        p.CreationDate
    FROM Posts p,
         UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagAggregates AS (
    SELECT
        Tag,
        COUNT(*) AS QuestionCount,
        AVG(Score) AS AvgScore,
        MAX(Score) AS MaxScore,
        MIN(Score) AS MinScore,
        COUNT(CASE WHEN CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY) THEN 1 END) AS RecentCount
    FROM TagUsageAndScore
    GROUP BY Tag
),
UserReputationWindow AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
        LEAD(Reputation) OVER (ORDER BY Reputation DESC) AS NextHigherReputation,
        LAG(Reputation) OVER (ORDER BY Reputation DESC) AS NextLowerReputation
    FROM Users
)
SELECT
    tpwr.PostId,
    tpwr.Title,
    tpwr.OwnerUserId,
    tpwr.OwnerName,
    tpwr.PostTypeId,
    tpwr.Score,
    tpwr.ViewCount,
    tpwr.UpVotesCount,
    tpwr.DownVotesCount,
    tpwr.CommentCount,
    tpwr.GoldBadges,
    tpwr.SilverBadges,
    tpwr.BronzeBadges,
    tpwr.BadgesLastYear,
    tpwr.LastBadgeDate,
    tpwr.ScoreRank,
    tpwr.ViewRank,
    cdp.CloseReasonName,
    cdp.DuplicateOfPostId,
    cdp.DuplicateOfTitle,
    COALESCE(ta.QuestionCount, 0) AS TagQuestionCount,
    COALESCE(ta.AvgScore, 0) AS TagAverageScore,
    COALESCE(ta.RecentCount, 0) AS TagRecentQuestions,
    urw.Reputation,
    urw.ReputationRank,
    urw.NextHigherReputation,
    urw.NextLowerReputation,
    CASE
        WHEN tpwr.ScoreRank <= 10 AND urw.Reputation >= 10000 THEN 'Top Contributor'
        WHEN tpwr.ScoreRank <= 50 THEN 'Frequent Contributor'
        ELSE 'Participant'
    END AS ContributorLevel,
    (COALESCE(tpwr.Title, '<No Title') ||
        ' - ' ||
        CASE WHEN tpwr.Tags IS NULL THEN '<No Tags>' ELSE SUBSTRING(tpwr.Tags FROM 2 FOR LENGTH(tpwr.Tags) - 2) END ||
        ' - ' ||
        COALESCE(tpwr.OwnerName, '<Anonymous>')
    ) AS CombinedTitleTagOwner
FROM
    TopPostsWithRanking tpwr
LEFT JOIN
    ClosedDuplicatePosts cdp ON tpwr.PostId = cdp.PostId
LEFT JOIN
    TagAggregates ta ON ta.Tag = (
        SELECT t FROM (
            SELECT t FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(tpwr.Tags FROM 2 FOR LENGTH(tpwr.Tags) - 2), '><')) AS t
        ) s LIMIT 1
    )
LEFT JOIN
    UserReputationWindow urw ON urw.Id = tpwr.OwnerUserId
WHERE 
    (tpwr.Score > 0 OR tpwr.ViewCount > 1000)

UNION ALL

SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    u.DisplayName,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    COALESCE(vt_up.VoteCount, 0) AS UpVotesCount,
    COALESCE(vt_down.VoteCount, 0) AS DownVotesCount,
    COALESCE(comm.CommentCount, 0) AS CommentCount,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS BadgesLastYear,
    DATE '1970-01-01' AS LastBadgeDate,
    0 AS ScoreRank,
    0 AS ViewRank,
    NULL AS CloseReasonName,
    NULL AS DuplicateOfPostId,
    NULL AS DuplicateOfTitle,
    NULL AS TagQuestionCount,
    NULL AS TagAverageScore,
    NULL AS TagRecentQuestions,
    u.Reputation,
    0 AS ReputationRank,
    NULL AS NextHigherReputation,
    NULL AS NextLowerReputation,
    'Unknown' AS ContributorLevel,
    (COALESCE(p.Title, '<No Title') ||
        ' - ' ||
        CASE WHEN p.Tags IS NULL THEN '<No Tags>' ELSE SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) END ||
        ' - ' ||
        COALESCE(u.DisplayName, '<Anonymous>')
    ) AS CombinedTitleTagOwner
FROM
    Posts p
INNER JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
) vt_up ON vt_up.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
) vt_down ON vt_down.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId
) comm ON comm.PostId = p.Id
WHERE p.PostTypeId = 1 AND p.Score <= 0 AND p.ViewCount <= 1000

ORDER BY ReputationRank NULLS LAST, Score DESC, ViewCount DESC
LIMIT 100;