-- {"query": "1440.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1791} 
WITH TagCounts AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count,
        COALESCE(p.ViewCount, 0) AS TotalViews,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY COALESCE(p.Score,0) DESC) rn
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.TagName IS NOT NULL
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= '2023-01-01' -- recent badges counted
    GROUP BY b.UserId
),
ComplexPostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        -- ratio of positive to negative votes
        GREATEST(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            1
        )::float / NULLIF(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),(0)
        )::float AS PosToNegVoteRatio,
        -- check user reputation at this date by correlation
        (SELECT u.Reputation FROM Users u WHERE u.Id = p.OwnerUserId AND u.CreationDate <= p.CreationDate ORDER BY u.CreationDate DESC LIMIT 1) AS UserReputationAtPostTime,
        -- count comments with text length more than average
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id AND LENGTH(c.Text) > (
             SELECT AVG(LENGTH(Text)) FROM Comments WHERE PostId = p.Id
        )) AS DetailedCommentCount,
        -- flag if has 'performance' or 'optimization' tags (case insensitive search)
        CASE WHEN p.Tags ~* 'performance|optimization' THEN 1 ELSE 0 END AS HasPerformanceTag,
        -- string expression: shortened title or body fallback
        COALESCE(
            NULLIF(SUBSTR(p.Title,1,60), ''),
            SUBSTR(p.Body,1,60),
            'No Title/Body'
        ) AS Snippet
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
LatestEditorInfo AS (
    SELECT 
        ph.PostId,
        ph.UserId AS LastEditorUserId,
        u.DisplayName AS LastEditorDisplayName,
        ph.CreationDate AS LastEditDate,
        RANK() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,14) -- Title, Body, Tags edits and Suggested Edits Applied
),
ActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        -- calculating activity span in days
        EXTRACT(day FROM (u.LastAccessDate - u.CreationDate)) AS ActivitySpanDays,
        COALESCE(ubc.GoldBadges,0) AS GoldBadges,
        COALESCE(ubc.SilverBadges,0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
        -- densely populated tag-based skill sums (posts in tags * badge counts)
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags ~* '^[<]?java[>]?$') * COALESCE(ubc.GoldBadges,0) AS JavaSkillIndex,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags ~* '^[<]?python[>]?$') * COALESCE(ubc.SilverBadges,0) AS PythonSkillIndex,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags ~* '^[<]?javascript[>]?$') * COALESCE(ubc.BronzeBadges,0) AS JavaScriptSkillIndex
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    WHERE u.LastAccessDate >= NOW() - INTERVAL '180 days' 
),
DuplicateQuestionPairs AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pq.Title AS PostTitle,
        rq.Title AS RelatedPostTitle,
        Users.DisplayName AS OwnerName
    FROM PostLinks pl
    JOIN Posts pq ON pq.Id = pl.PostId AND pq.PostTypeId = 1
    JOIN Posts rq ON rq.Id = pl.RelatedPostId AND rq.PostTypeId = 1
    LEFT JOIN Users ON Users.Id = pq.OwnerUserId
    WHERE pl.LinkTypeId = 3 -- Duplicates
),
TopAnswersWithWindow AS (
    SELECT
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2 -- Answer
)
SELECT 
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.ActivitySpanDays,
    u.JavaSkillIndex,
    u.PythonSkillIndex,
    u.JavaScriptSkillIndex,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.Snippet AS PostSnippet,
    p.PosToNegVoteRatio,
    p.DetailedCommentCount,
    p.HasPerformanceTag,
    le.LastEditorUserId,
    le.LastEditorDisplayName,
    le.LastEditDate,
    dupPairs.DuplicateCount,
    tp.AnswerId,
    tp.AnswerScore,
    tc.TagRenderCount,
    generally popular tag triads
FROM 
    ActiveUsers u
INNER JOIN ComplexPostStats p 
    ON p.OwnerUserId = u.Id 
LEFT JOIN (
    SELECT 
        PostId, 
        MAX(CASE WHEN rn = 1 THEN LastEditorUserId END) AS LastEditorUserId,
        MAX(CASE WHEN rn = 1 THEN LastEditorDisplayName END) AS LastEditorDisplayName,
        MAX(CASE WHEN rn = 1 THEN LastEditDate END) AS LastEditDate
    FROM LatestEditorInfo 
    GROUP BY PostId
) le ON le.PostId = p.Id
LEFT JOIN (
    SELECT
        pq.OwnerUserId,
        COUNT(DISTINCT pl.PostId) AS DuplicateCount
    FROM PostLinks pl
    JOIN Posts pq ON pq.Id = pl.PostId
    WHERE pl.LinkTypeId = 3
    GROUP BY pq.OwnerUserId
) dupPairs ON dupPairs.OwnerUserId = u.Id
LEFT JOIN (
    SELECT 
        q.ParentId, 
        MAX(q.Id) AS AnswerId,
        MAX(q.Score) AS AnswerScore
    FROM TopAnswersWithWindow q
    WHERE q.AnswerRank = 1
    GROUP BY q.ParentId
) tp ON tp.ParentId = p.Id
LEFT JOIN (
    SELECT 
        TagName, 
        SUM(Count) AS TagRenderCount
    FROM Tags 
    WHERE TagName IN (SELECT UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(Tags,'<',''),'>',''),' ')) FROM Posts WHERE Posts.OwnerUserId IS NOT NULL)
    GROUP BY TagName
    LIMIT 3
) tc ON TRUE
WHERE 
    p.CreationDate >= NOW() - INTERVAL '365 days'
AND 
    p.Score > 5
ORDER BY 
    u.Reputation DESC, 
    p.Score DESC
LIMIT 100;