-- {"query": "4073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1453} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.ViewCount, 0) AS TagViewCount,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT
        th.Id,
        th.TagName,
        th.TagViewCount + COALESCE(p2.ViewCount, 0),
        rh.Level + 1
    FROM RecursiveTagHierarchy rh
    JOIN Posts p2 ON p2.Tags LIKE '%' || rh.TagName || '%'
    JOIN Tags th ON th.TagName = rh.TagName
    WHERE rh.Level < 3
),
UserBadgeRanks AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        AVG(COALESCE(p.Score, 0)) FILTER(WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
        MAX(b.Class) AS HighestBadgeClass
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostVotesSummary AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS RankByScore
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.Score
),
CommentCorrelations AS (
    SELECT
        c.PostId,
        u.Id AS UserId,
        u.DisplayName,
        MAX(c.Score) AS MaxCommentScore,
        COUNT(*) AS CommentCount
    FROM Comments c
    LEFT JOIN Users u ON u.Id = c.UserId
    WHERE c.CreationDate > NOW() - INTERVAL '6 months'
    GROUP BY c.PostId, u.Id, u.DisplayName
),
AnswerQualityRanks AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        u.DisplayName AS Answerer,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank,
        COALESCE((SELECT COUNT(1) 
                  FROM Votes v 
                  WHERE v.PostId = a.Id AND v.VoteTypeId = 8), 0) AS BountyStarts
    FROM Posts a
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
),
DuplicateLinks AS (
    SELECT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId,
        p.Title AS OriginalTitle,
        pl.CreationDate AS LinkDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name = 'Duplicate'
    JOIN Posts p ON p.Id = pl.RelatedPostId
    WHERE pl.CreationDate > NOW() - INTERVAL '2 years'
),
FinalSelection AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        us.DisplayName AS OwnerName,
        p.Score,
        COALESCE(pv.UpVotes - pv.DownVotes, 0) AS NetVotes,
        COALESCE(ac.MaxCommentScore, 0) AS MaxCommentScore,
        COALESCE(ac.CommentCount, 0) AS CommentCount,
        COALESCE(aqr.AnswerRank, NULL) AS AnswerRank,
        COALESCE(aqr.BountyStarts, 0) AS BountiesStarted,
        COALESCE(dq.OriginalTitle, 'N/A') AS OriginalDuplicateTitle,
        usr.BadgeCount,
        usr.HighestBadgeClass,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, pv.UpVotes DESC) AS OverallRank
    FROM Posts p
    LEFT JOIN Users us ON us.Id = p.OwnerUserId
    LEFT JOIN PostVotesSummary pv ON pv.Id = p.Id
    LEFT JOIN CommentCorrelations ac ON ac.PostId = p.Id AND ac.UserId = p.OwnerUserId
    LEFT JOIN AnswerQualityRanks aqr ON aqr.AnswerId = p.Id
    LEFT JOIN DuplicateLinks dq ON dq.DuplicatePostId = p.Id
    LEFT JOIN UserBadgeRanks usr ON usr.UserId = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
)
SELECT
    fs.PostId,
    fs.Title,
    CASE fs.PostTypeId WHEN 1 THEN 'Question' WHEN 2 THEN 'Answer' ELSE 'Other' END AS PostType,
    fs.OwnerName,
    fs.Score,
    fs.NetVotes,
    fs.MaxCommentScore,
    fs.CommentCount,
    fs.AnswerRank,
    fs.BountiesStarted,
    fs.OriginalDuplicateTitle,
    fs.BadgeCount,
    CASE fs.HighestBadgeClass
        WHEN 1 THEN 'Gold'
        WHEN 2 THEN 'Silver'
        WHEN 3 THEN 'Bronze'
        ELSE 'None'
    END AS HighestBadge,
    fs.OverallRank,
    -- Complex string expression combining title and duplicate info, handling nulls
    CONCAT_WS(' | ',
        UPPER(COALESCE(fs.Title, 'NO TITLE')),
        'Duplicate Of: ' || COALESCE(NULLIF(fs.OriginalDuplicateTitle, 'N/A'), 'None'),
        'Owner: ' || COALESCE(fs.OwnerName, 'Anonymous'),
        'Badges: ' || COALESCE(CAST(fs.BadgeCount AS VARCHAR), '0')
    ) AS Summary,
    -- Conditional expression with NULL logic and date diff from last access for complexity
    CASE
        WHEN fs.Score > 100 AND fs.BountiesStarted > 0 THEN 'Highly Valued Bountied Post'
        WHEN fs.Score BETWEEN 50 AND 100 THEN 'Well Rated Post'
        ELSE 'Regular Post'
    END AS PostCategory
FROM FinalSelection fs
WHERE fs.OverallRank <= 50
ORDER BY fs.PostTypeId, fs.OverallRank;
