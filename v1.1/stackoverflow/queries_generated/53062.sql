-- {"query": "53062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1119} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM 
        Votes v
    JOIN 
        Posts p ON v.PostId = p.Id
    WHERE 
        v.CreationDate > '2020-01-01'
    GROUP BY 
        v.PostId, p.OwnerUserId
    HAVING 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 5
),
CommentMetrics AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.UserId
),
PostHistoryEdits AS (
    SELECT 
        ph.PostId,
        p.OwnerUserId AS UserId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    JOIN 
        Posts p ON ph.PostId = p.Id
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)  -- Edit types
    GROUP BY 
        ph.PostId, p.OwnerUserId
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsage,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
UserTopTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagPostCount
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1  -- Questions
    GROUP BY 
        p.OwnerUserId, TagName
    HAVING 
        COUNT(*) > 5
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalPostScore,
    ua.AvgViewCount,
    ua.LastPostDate,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.BadgeNames,
    va.Upvotes,
    va.Downvotes,
    va.TotalVotes,
    cm.CommentCount,
    cm.AvgCommentScore,
    phe.EditCount,
    phe.LastEditDate,
    tp.TagName AS PopularTag,
    tp.TagUsage,
    tp.TagRank,
    utt.TagName AS UserTopTag,
    utt.TagPostCount,
    RANK() OVER (PARTITION BY ua.UserId ORDER BY utt.TagPostCount DESC) AS UserTagRank
FROM 
    UserActivity ua
LEFT JOIN 
    BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN 
    (SELECT UserId, SUM(Upvotes) AS Upvotes, SUM(Downvotes) AS Downvotes, SUM(TotalVotes) AS TotalVotes 
     FROM VoteAnalysis GROUP BY UserId) va ON ua.UserId = va.UserId
LEFT JOIN 
    CommentMetrics cm ON ua.UserId = cm.UserId
LEFT JOIN 
    (SELECT UserId, SUM(EditCount) AS EditCount, MAX(LastEditDate) AS LastEditDate 
     FROM PostHistoryEdits GROUP BY UserId) phe ON ua.UserId = phe.UserId
LEFT JOIN 
    UserTopTags utt ON ua.UserId = utt.UserId
LEFT JOIN 
    TagPopularity tp ON utt.TagName = tp.TagName
WHERE 
    ua.Reputation > 1000
    AND (bs.GoldBadges > 0 OR ua.PostCount > 50)
ORDER BY 
    ua.Reputation DESC, ua.PostCount DESC
LIMIT 1000;
