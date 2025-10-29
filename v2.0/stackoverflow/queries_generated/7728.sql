-- {"query": "7728.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2137} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Other'
    END as PostType,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    COALESCE(p.CommentCount, 0) as CommentCount,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    p.Tags,
    CASE 
        WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
            (SELECT COUNT(*) FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag WHERE tag != '')
        ELSE 0
    END as TagCount,
    p.ClosedDate,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 
            (SELECT Name FROM CloseReasonTypes WHERE Id = (
                SELECT CAST(SUBSTRING(ph.Comment FROM 2) AS INTEGER) 
                FROM PostHistory ph 
                WHERE ph.PostId = p.Id 
                AND ph.PostHistoryTypeId = 10 
                ORDER BY ph.CreationDate DESC 
                LIMIT 1
            ))
        ELSE NULL
    END as CloseReason,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 
        0
    ) as CommentCountWithNull,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
    COALESCE(
        (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8),
        0
    ) as AvgBountyAmount,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as LastVoteDate,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
            (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId)
        ELSE NULL 
    END as AcceptedAnswerScore,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as PostRankByType,
    LAG(p.CreationDate) OVER (ORDER BY p.CreationDate) as PreviousPostCreationDate,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
    PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
    NTILE(100) OVER (ORDER BY p.Score) as ScoreQuintile,
    LEAD(p.Id) OVER (ORDER BY p.Score DESC) as NextHigherScorePostId,
    FIRST_VALUE(p.Id) OVER (ORDER BY p.Score DESC) as HighestScoringPostId,
    NTH_VALUE(p.Id, 5) OVER (ORDER BY p.Score DESC) as FifthHighestScoringPostId,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostRank,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostLinks pl 
            WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) THEN 'HasDuplicateLink' 
        ELSE 'NoDuplicateLink' 
    END as DuplicateLinkStatus,
    COALESCE(
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)),
        0
    ) as EditHistoryCount,
    CASE 
        WHEN p.PostTypeId = 1 THEN 
            (SELECT STRING_AGG(b.Name, ', ') 
             FROM Badges b 
             WHERE b.UserId = p.OwnerUserId 
             AND b.Name IN ('Yearling', 'Populist', 'Guru', 'Notable Question', 'Famous Question'))
        ELSE NULL
    END as UserSpecialBadges,
    CASE 
        WHEN p.PostTypeId = 1 THEN 
            (SELECT ROUND(AVG(Score), 2) 
             FROM Posts p2 
             WHERE p2.ParentId = p.Id 
             AND p2.PostTypeId = 2
             AND p2.Score IS NOT NULL)
        ELSE NULL
    END as AvgAnswerScore,
    CASE 
        WHEN p.PostTypeId = 1 
        AND p.OwnerUserId IS NOT NULL 
        AND p.OwnerUserId != -1 
        AND EXISTS (
            SELECT 1 FROM Posts p3 
            WHERE p3.ParentId = p.Id 
            AND p3.PostTypeId = 2 
            AND p3.Score > 0
        ) THEN 'HasNonZeroAnswer'
        ELSE 'NoNonZeroAnswer'
    END as QuestionAnswerStatus,
    (SELECT STRING_AGG(c.Text, ' | ' ORDER BY c.CreationDate) 
     FROM Comments c 
     WHERE c.PostId = p.Id 
     AND c.Score > 0
     LIMIT 5) as TopComments,
    CASE 
        WHEN p.ViewCount > (
            SELECT AVG(ViewCount) 
            FROM Posts 
            WHERE PostTypeId = 1
        ) THEN 'AboveAvgViews'
        ELSE 'BelowAvgViews'
    END as ViewPerformance,
    (SELECT COUNT(DISTINCT UserId) 
     FROM Votes 
     WHERE PostId = p.Id 
     AND VoteTypeId IN (2,3)) as UniqueVoters,
    (CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 1 ELSE 0 END) +
    (CASE WHEN p.Body IS NOT NULL AND p.Body != '' THEN 1 ELSE 0 END) +
    (CASE WHEN p.Title IS NOT NULL AND p.Title != '' THEN 1 ELSE 0 END) as ContentCompletenessMetric,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts p4 WHERE p4.ParentId = p.Id AND p4.PostTypeId = 2) > 3 THEN 'ManyAnswers'
        WHEN (SELECT COUNT(*) FROM Posts p4 WHERE p4.ParentId = p.Id AND p4.PostTypeId = 2) > 0 THEN 'FewAnswers'
        ELSE 'NoAnswers'
    END as AnswerDistribution,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Date >= '2020-01-01') as RecentBadgesCount,
    EXTRACT(YEAR FROM p.CreationDate) as PostYear,
    EXTRACT(MONTH FROM p.CreationDate) as PostMonth,
    EXTRACT(DAY FROM p.CreationDate) as PostDay,
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.OwnerUserId = p.OwnerUserId AND p5.CreationDate >= '2020-01-01') as UserPostsInYear,
    COALESCE(p.LastActivityDate, p.CreationDate) as EffectiveLastActivityDate,
    CASE 
        WHEN p.PostTypeId = 2 
        AND p.ParentId IS NOT NULL 
        AND EXISTS (
            SELECT 1 FROM Posts p6 
            WHERE p6.Id = p.ParentId 
            AND p6.PostTypeId = 1
        ) THEN 'ValidAnswerToQuestion'
        ELSE 'InvalidLink'
    END as AnswerValidation,
    CASE 
        WHEN (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 17) > 0 
        THEN 'MigratedPost'
        ELSE 'OriginalPost'
    END as MigrationStatus
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as VoteCount
    FROM Votes 
    WHERE VoteTypeId IN (2,3)
    GROUP BY PostId
) v ON p.Id = v.PostId
WHERE p.CreationDate >= '2020-01-01'
    AND p.CreationDate <= '2020-12-31'
    AND (
        (p.PostTypeId IN (1,2) AND p.Score IS NOT NULL)
        OR (p.PostTypeId = 1 AND p.AnswerCount >= 0)
        OR (p.PostTypeId = 2 AND p.Score IS NOT NULL)
    )
    AND (
        (p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1)
        OR (p.OwnerDisplayName IS NOT NULL AND p.OwnerDisplayName != '')
    )
    AND (
        (p.Tags IS NOT NULL AND p.Tags != '')
        OR (p.Body IS NOT NULL AND p.Body != '')
        OR (p.Title IS NOT NULL AND p.Title != '')
    )
    AND p.ViewCount IS NOT NULL
    AND p.ViewCount >= 0
    AND p.Score IS NOT NULL
    AND p.Score >= -100
    AND p.Score <= 10000
    AND (
        EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3))
        OR EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id)
        OR EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id)
        OR p.PostTypeId = 1
    )
    AND (
        (p.PostTypeId = 1 AND (p.AnswerCount > 0 OR p.CommentCount > 0))
        OR (p.PostTypeId = 2 AND p.Score IS NOT NULL)
        OR (p.PostTypeId = 3 OR p.PostTypeId = 5 OR p.PostTypeId = 4)
    )
ORDER BY p.CreationDate DESC, p.Score DESC
LIMIT 10000;