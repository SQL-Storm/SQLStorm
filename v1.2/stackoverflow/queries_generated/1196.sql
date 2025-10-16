-- {"query": "1196.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1627} 

WITH RecursiveTagHits AS (
    SELECT 
        p.Id AS PostId,
        LOWER(TRIM(t.TagName)) AS TagName,
        p.CreationDate,
        COUNT(*) OVER (PARTITION BY LOWER(TRIM(t.TagName))) AS TagGlobalCount
    FROM 
        Posts p
        CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><')) AS t(TagName)
    WHERE 
        p.PostTypeId = 1
),
BadgeFiltering AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class, b.Date DESC) AS RN
    FROM 
        Badges b
    WHERE 
        b.TagBased = 0 
        AND b.Class IN (1,2) -- Gold and Silver badges only for test
),
QualifiedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(COALESCE(vt.UpVotes,0) - COALESCE(vt.DownVotes,0)), 0) AS VoteBalance,
        COUNT(DISTINCT b.Name) FILTER (WHERE b.RN = 1) AS DistinctTopBadges,
        RANK() OVER (ORDER BY u.Reputation DESC, VoteBalance DESC) AS UserRank
    FROM 
        Users u
        LEFT JOIN (
            SELECT 
                UserId, 
                SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
            FROM Votes v
            GROUP BY UserId
        ) vt ON vt.UserId = u.Id
        LEFT JOIN BadgeFiltering b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        AVG(a.Score) FILTER (WHERE a.CreationDate >= q.CreationDate) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM 
        Posts q
        LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE 
        q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags
),
CloseReasonsCount AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        MAX(CAST(ph.Comment AS SMALLINT)) FILTER (WHERE ph.PostHistoryTypeId = 10) AS DominantCloseReasonId,
        MAX(cr.Name) AS DominantCloseReasonName
    FROM 
        PostHistory ph
        LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS SMALLINT)
    WHERE 
        ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
UserPostComplex AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        COALESCE(c.CloseVotes,0) AS CloseVotes,
        COALESCE(c.DominantCloseReasonName,'N/A') AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS UserTopPostRank
    FROM 
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN CloseReasonsCount c ON c.PostId = p.Id
    WHERE
        p.PostTypeId IN (1,2)
),
UserActivityWindow AS (
    SELECT 
        ua.UserId,
        ua.PostTypeId,
        ua.PostId,
        ua.CreationDate,
        ua.Score,
        SUM(ua.Score) OVER (PARTITION BY ua.UserId ORDER BY ua.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore,
        COUNT(*) OVER (PARTITION BY ua.UserId ORDER BY ua.CreationDate ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS RemainingPosts,
        ua.UserTopPostRank
    FROM 
        UserPostComplex ua
),
UnionPostsAnswers AS (
    SELECT 
        Id, PostTypeId, CreationDate, Score, Title
    FROM 
        Posts
    WHERE 
        PostTypeId IN (1,2)

    INTERSECT

    SELECT 
        Id, PostTypeId, CreationDate, Score, Title
    FROM 
        Posts
    WHERE 
        Score > 10 AND ViewCount > 1000
)
SELECT 
    q.Id AS QuestionId,
    q.Title,
    qq.TotalAnswers,
    qq.AvgAnswerScore,
    qq.LastAnswerDate,
    rh.TagName,
    rh.TagGlobalCount,
    qu.DisplayName AS UserDisplayName,
    qu.Reputation AS UserReputation,
    qu.DistinctTopBadges,
    qu.VoteBalance,
    COALESCE(c.CloseVotes, 0) AS CloseVotes,
    c.DominantCloseReasonName,
    ua.CumulativeScore,
    ua.RemainingPosts,
    ua.UserTopPostRank,
    COALESCE(pl.LinkCount,0) AS NumberOfLinkedPosts,
    CASE 
        WHEN q.ViewCount IS NULL OR q.ViewCount = 0 THEN NULL 
        ELSE ROUND(((q.Score::numeric / NULLIF(q.ViewCount,0)) * 100)::numeric, 2)
    END AS ScorePer100Views,
    CASE 
        WHEN LENGTH(coalesce(q.Title, '')) = 0 THEN 'No Title'
        ELSE LOWER(q.Title)
    END AS LowerTitle,
    STRING_AGG(DISTINCT CONCAT(bf.Name, ':', bf.Class), ', ') FILTER (WHERE bf.RN = 1) AS TopBadgesStrings
FROM 
    Posts q
    INNER JOIN PostAnswerStats qq ON qq.QuestionId = q.Id
    LEFT JOIN RecursiveTagHits rh ON rh.PostId = q.Id
    LEFT JOIN QualifiedUsers qu ON qu.Id = q.OwnerUserId
    LEFT JOIN CloseReasonsCount c ON c.PostId = q.Id
    LEFT JOIN UserActivityWindow ua ON ua.PostId = q.Id
    LEFT JOIN (
        SELECT 
            PostId, COUNT(*) AS LinkCount 
        FROM PostLinks 
        GROUP BY PostId
    ) pl ON pl.PostId = q.Id
    LEFT JOIN BadgeFiltering bf ON bf.UserId = q.OwnerUserId AND bf.RN = 1
WHERE 
    q.PostTypeId = 1
    AND q.Score > 5
    AND (c.CloseVotes IS NULL OR c.CloseVotes < 5)
    AND qu.UserRank <= 100
GROUP BY 
    q.Id, q.Title, qq.TotalAnswers, qq.AvgAnswerScore, qq.LastAnswerDate, rh.TagName, rh.TagGlobalCount, 
    qu.DisplayName, qu.Reputation, qu.DistinctTopBadges, qu.VoteBalance, c.CloseVotes, c.DominantCloseReasonName,
    ua.CumulativeScore, ua.RemainingPosts, ua.UserTopPostRank, pl.LinkCount, q.ViewCount
ORDER BY 
    ua.CumulativeScore DESC NULLS LAST,
    qa.AvgAnswerScore DESC NULLS LAST,
    qu.Reputation DESC NULLS LAST
LIMIT 50;
