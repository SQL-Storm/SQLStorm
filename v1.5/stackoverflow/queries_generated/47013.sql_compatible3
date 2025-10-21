WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        CAST(t.TagName AS VARCHAR(1000)) AS tag_path,
        1 AS level
    FROM Tags t
    WHERE t.Count > 10000
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        CAST(th.tag_path || ' -> ' || t2.TagName AS VARCHAR(1000)) AS tag_path,
        th.level + 1 AS level
    FROM Tags t2
    INNER JOIN tag_hierarchy th ON th.Id != t2.Id
    WHERE t2.Count BETWEEN 5000 AND 10000
    AND th.level < 3
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT b.Name) AS UniqueBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STDDEV(p.Score) AS ScoreStdDev
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    AND u.CreationDate < CAST('2024-10-01' AS DATE) - INTERVAL '365 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
post_evolution AS (
    SELECT 
        ph.PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN ph.Id END) AS RollbackCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenCount,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate END) AS LastEditDate,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END, ', ') AS CloseReasons
    FROM PostHistory ph
    INNER JOIN Posts p ON ph.PostId = p.Id
    WHERE p.Score > 5
    GROUP BY ph.PostId, p.PostTypeId, p.CreationDate
),
voting_patterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS Bounties,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        CAST(COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS FLOAT) / 
            NULLIF(COUNT(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 END), 0) AS UpVoteRatio
    FROM Votes v
    WHERE v.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '730 days'
    GROUP BY v.PostId
),
linked_posts AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        p1.Score AS PostScore,
        p2.Score AS RelatedPostScore,
        p1.ViewCount AS PostViews,
        p2.ViewCount AS RelatedViews,
        lt.Name AS LinkType,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY p2.Score DESC) AS RelatedRank
    FROM PostLinks pl
    INNER JOIN Posts p1 ON pl.PostId = p1.Id
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE p1.Score > 0 AND p2.Score > 0
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.Questions,
    ue.Answers,
    ue.TotalScore,
    ROUND(CAST(ue.AvgScore AS NUMERIC), 2) AS AvgScore,
    ROUND(CAST(ue.MedianScore AS NUMERIC), 2) AS MedianScore,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    COUNT(DISTINCT pe.PostId) AS EditedPosts,
    AVG(pe.EditCount) AS AvgEditsPerPost,
    AVG(pe.UniqueEditors) AS AvgEditorsPerPost,
    SUM(vp.UpVotes) AS TotalUpVotesReceived,
    SUM(vp.DownVotes) AS TotalDownVotesReceived,
    AVG(vp.UpVoteRatio) AS AvgUpVoteRatio,
    SUM(vp.TotalBountyAmount) AS TotalBountiesReceived,
    COUNT(DISTINCT lp.RelatedPostId) AS LinkedPostCount,
    AVG(lp.RelatedPostScore) AS AvgLinkedPostScore,
    STRING_AGG(DISTINCT th.TagName, ', ') FILTER (WHERE th.level = 1) AS TopTags,
    DENSE_RANK() OVER (ORDER BY ue.TotalScore DESC) AS ScoreRank,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) AS ReputationRank,
    NTILE(100) OVER (ORDER BY ue.AvgScore) AS ScorePercentile
FROM user_expertise ue
LEFT JOIN Posts p ON ue.UserId = p.OwnerUserId
LEFT JOIN post_evolution pe ON p.Id = pe.PostId
LEFT JOIN voting_patterns vp ON p.Id = vp.PostId
LEFT JOIN linked_posts lp ON p.Id = lp.PostId AND lp.RelatedRank <= 5
LEFT JOIN LATERAL (
    SELECT DISTINCT unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag_name
) AS pt ON TRUE
LEFT JOIN tag_hierarchy th ON pt.tag_name = th.TagName
WHERE ue.TotalScore > 100
GROUP BY 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.Questions,
    ue.Answers,
    ue.TotalScore,
    ue.AvgScore,
    ue.MedianScore,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges
HAVING COUNT(DISTINCT pe.PostId) > 5
ORDER BY ue.TotalScore DESC
LIMIT 100;