-- {"query": "7007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1708} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
        ELSE 'Unknown'
    END as PostTypeName,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
        0
    ) as CommentCountActual,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
        0
    ) as UpVoteCount,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
        0
    ) as DownVoteCount,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5),
        0
    ) as FavoriteCountActual,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Name LIKE '%Nice%' OR b.Name LIKE '%Good%' OR b.Name LIKE '%Great%'),
        0
    ) as QualityBadgeCount,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END as PostStatus,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankWithinType,
    RANK() OVER (ORDER BY p.Score DESC) as ScoreRankOverall,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
    AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
    NTILE(100) OVER (ORDER BY p.Score) as ScorePercentile,
    LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
    LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
    p.Score - LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as ScoreChange,
    CONCAT('Post #', p.Id, ' - ', p.Title) as PostTitleDisplay,
    UPPER(SUBSTRING(p.Title, 1, 1)) as FirstLetter,
    CASE 
        WHEN p.Title LIKE '%SQL%' THEN 'SQL Related'
        WHEN p.Title LIKE '%Python%' THEN 'Python Related'
        WHEN p.Title LIKE '%Java%' THEN 'Java Related'
        WHEN p.Title LIKE '%C#' THEN 'C# Related'
        WHEN p.Title LIKE '%JavaScript%' THEN 'JavaScript Related'
        ELSE 'Other'
    END as TopicCategory,
    COALESCE(
        (SELECT COUNT(DISTINCT UserId) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)),
        0
    ) as UniqueVoters,
    COALESCE(
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3),
        0
    ) as DuplicateLinkCount,
    COALESCE(
        (SELECT COUNT(DISTINCT UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13)),
        0
    ) as ActivityUserCount,
    CASE 
        WHEN p.AnswerCount > 0 THEN (p.Score * 1.0 / p.AnswerCount)
        ELSE 0 
    END as AvgScorePerAnswer,
    CASE 
        WHEN p.CommentCount > 0 THEN (p.Score * 1.0 / p.CommentCount)
        ELSE 0 
    END as AvgScorePerComment,
    CASE 
        WHEN p.ViewCount > 0 THEN (p.Score * 1.0 / p.ViewCount)
        ELSE 0 
    END as ScorePerView,
    p.Tags,
    SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) as RawTags,
    STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') as TagArray,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCountActual,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.ParentId = p.Id AND p3.PostTypeId = 2 AND p3.Score > 0) as PositiveAnswerCount,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.ParentId = p.Id AND p4.PostTypeId = 2 AND p4.Score < 0) as NegativeAnswerCount,
    (SELECT AVG(p5.Score) FROM Posts p5 WHERE p5.ParentId = p.Id AND p5.PostTypeId = 2) as AvgAnswerScore,
    (SELECT MAX(p6.Score) FROM Posts p6 WHERE p6.ParentId = p.Id AND p6.PostTypeId = 2) as MaxAnswerScore,
    (SELECT MIN(p7.Score) FROM Posts p7 WHERE p7.ParentId = p.Id AND p7.PostTypeId = 2) as MinAnswerScore
FROM Posts p
INNER JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN Posts parent ON parent.Id = p.ParentId
LEFT JOIN Posts accepted ON accepted.Id = p.AcceptedAnswerId
WHERE p.PostTypeId IN (1,2)
    AND p.CreationDate >= '2022-01-01 00:00:00'
    AND (p.Score > 5 OR p.ViewCount > 100 OR p.CommentCount > 10)
    AND (p.Tags IS NOT NULL AND p.Tags != '')
    AND u.Reputation > 1000
    AND (
        p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
        OR p.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
    )
    AND EXISTS (
        SELECT 1 FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.CreationDate >= '2022-01-01 00:00:00'
        AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)
    )
    AND NOT EXISTS (
        SELECT 1 FROM Badges b 
        WHERE b.UserId = p.OwnerUserId 
        AND b.Name IN ('Popular Question', 'Notable Question', 'Yearling', 'Great Question')
        AND b.Date >= '2022-01-01 00:00:00'
    )
    AND (
        COALESCE((SELECT COUNT(*) FROM Posts p8 WHERE p8.ParentId = p.Id AND p8.PostTypeId = 2), 0) >= 
        (
            SELECT AVG(AnswerCount) 
            FROM Posts 
            WHERE PostTypeId = 1 
            AND Score > 10 
            AND CreationDate >= '2022-01-01 00:00:00'
        )
    )
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;