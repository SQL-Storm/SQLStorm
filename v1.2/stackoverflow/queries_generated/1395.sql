-- {"query": "1395.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1702} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name END) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostDetails AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags, '') AS Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.LastActivityDate,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        
        -- Calculated field for tag count using String processing and NULL-safe checks
        (SELECT COUNT(*) FROM unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) AS tag ) AS TagCount
        
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
AnswerStats AS (
    SELECT 
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(COALESCE(vt.VoteCounts,0)) AS TotalAnswerVotes
    FROM Posts p
    LEFT JOIN (
        SELECT v.PostId, COUNT(*) AS VoteCounts
        FROM Votes v
        WHERE v.VoteTypeId IN (2,3)
        GROUP BY v.PostId
    ) vt ON p.Id = vt.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
QuestionCloseStats AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS NumCloseVotes,       -- Post Closed
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS NumReopenVotes,
        MAX(crt.Name) AS CloseReasonNames
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id AND ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
TopActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS RankByPosts,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) AS RankByComments,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountiesAwarded
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (8,9)
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10 OR COUNT(DISTINCT c.Id) > 10
),
QuestionAndAnswerUnion AS (
    SELECT 
        p.Id,
        'Question' AS PostRootType,
        p.Score,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    
    UNION ALL
    
    SELECT
        p.Id,
        'Answer' AS PostRootType,
        p.Score,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
),
RankedPostsWindow AS (
    SELECT 
        PostRootType,
        CreationDate,
        Id,
        Score,
        OwnerDisplayName,
        RANK() OVER (PARTITION BY PostRootType ORDER BY Score DESC, CreationDate ASC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY PostRootType ORDER BY CreationDate DESC) AS RecentRowNum
    FROM QuestionAndAnswerUnion
)
SELECT
    pd.Id AS PostId,
    pd.PostTypeName,
    pd.Title,
    pd.ViewCount,
    pd.Score,
    pd.AnswerCount,
    pd.FavoriteCount,
    CASE WHEN pd.AcceptedAnswerId IS NULL THEN 'No accepted answer' ELSE 'Has accepted answer' END AS AcceptedAnswerStatus,
    CASE 
        WHEN qs.NumCloseVotes > qs.NumReopenVotes THEN 'Currently Closed' 
        WHEN qs.NumCloseVotes = qs.NumReopenVotes AND qs.NumCloseVotes > 0 THEN 'Reopen Pending'
        ELSE 'Open' 
    END AS PostStatus,
    COALESCE(qs.CloseReasonNames, 'N/A') AS CloseReasons,
    usc.DisplayName AS OwnerUserDisplay,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TagBasedBadges,
    asv.AnswerCount AS CalculatedAnswerCount,
    ROUND(asv.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    asv.MaxAnswerScore,
    asv.TotalAnswerVotes,
    ta.RankByPosts,
    ta.RankByComments,
    ta.TotalBountiesAwarded,
    rp.ScoreRank,
    rp.RecentRowNum,
    -- Complex Expression: Influentiality Score with NULL-safe arithmetic & string manipulation
    CONCAT(
        'Influence_',
        pd.OwnerUserId,
        '_',
        COALESCE(CAST(
            (pd.Score * 0.4 + COALESCE(asv.AvgAnswerScore,0) * 0.3 + ubc.GoldBadges * 5 + COALESCE(ta.TotalBountiesAwarded, 0) * 2)
            AS varchar)
        ,'0')
    ) AS InfluentialityTag,
    -- Correlated Subquery demonstrating NULL logic and string aggregation
    (
        SELECT STRING_AGG(DISTINCT phtext, ', ' ORDER BY phtext)
        FROM (
            SELECT DISTINCT COALESCE(pht.Name, 'Unknown') AS phtext
            FROM PostHistory ph
            LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
            WHERE ph.PostId = pd.Id
        ) AS sub
    ) AS HistoryTypesConcatenated,
    -- Outer join for placeholder tag extraction with NULL logic
    COALESCE(
        (SELECT tag.TagName 
         FROM Tags tag 
         WHERE tag.ExcerptPostId = pd.Id 
         LIMIT 1), 
    'NoTag') AS PrimaryTag
    
FROM PostDetails pd

LEFT JOIN QuestionCloseStats qs ON qs.PostId = pd.Id
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = pd.OwnerUserId
LEFT JOIN AnswerStats asv ON asv.QuestionId = pd.Id
LEFT JOIN TopActiveUsers ta ON ta.DisplayName = ubc.DisplayName
LEFT JOIN RankedPostsWindow rp ON rp.Id = pd.Id
LEFT JOIN Users usc ON usc.Id = pd.OwnerUserId

WHERE pd.PostTypeId = 1
  AND (
        (pd.Score > 10 AND pd.ViewCount > 1000)
        OR pd.FavoriteCount > 5
      )
ORDER BY pd.Score DESC, pd.ViewCount DESC
LIMIT 100;