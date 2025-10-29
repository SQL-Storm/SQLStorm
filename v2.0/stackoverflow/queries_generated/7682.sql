-- {"query": "7682.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1577} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 1 THEN 'Question'
        ELSE 'Other'
    END as PostTypeDescription,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    COALESCE(p.CommentCount, 0) as CommentCount,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as TotalBounty,
    (SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.TagBased = 0) as UserBadges,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (
        SELECT DISTINCT unnest(string_to_array(trim(p.Tags, '<>'), '><')) as TagName
    ) t) as TagsList,
    (SELECT 
        CASE 
            WHEN COUNT(*) > 0 THEN 'Has History'
            ELSE 'No History'
        END
    FROM PostHistory ph 
    WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,12,13)
    ) as HistoryStatus,
    (SELECT 
        COUNT(*)
    FROM PostLinks pl
    WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) as DuplicateCount,
    (SELECT 
        STRING_AGG(lt.Name, ' | ')
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.PostId = p.Id
    ) as LinkTypes,
    (SELECT 
        MAX(ph.CreationDate)
    FROM PostHistory ph
    WHERE ph.PostId = p.Id
    ) as LastActivityDate,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRankInUser,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC, p.Score DESC) as RowNumber,
    NTH_VALUE(p.Score, 1) OVER (ORDER BY p.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MaxScore,
    LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
    LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
    AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAverage,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment LIKE '%101%'
        ) THEN 'Duplicate Closed'
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment LIKE '%102%'
        ) THEN 'Off-topic Closed'
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        ) THEN 'Other Closed'
        ELSE 'Not Closed'
    END as ClosureType,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
            (SELECT 
                STRING_AGG(CONCAT(a.OwnerDisplayName, ': ', a.Score), '; ')
                FROM Posts a 
                WHERE a.ParentId = p.Id AND a.PostTypeId = 2
                ORDER BY a.Score DESC
                LIMIT 3
            )
        ELSE NULL
    END as TopAnswers,
    CASE 
        WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0 THEN 
            (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId = 1)
        ELSE 0
    END as TotalQuestionsAsked,
    CASE 
        WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0 THEN 
            (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = p.OwnerUserId AND p3.PostTypeId = 2)
        ELSE 0
    END as TotalAnswersGiven,
    CASE 
        WHEN p.Score > 100 THEN 'Highly Voted'
        WHEN p.Score > 50 THEN 'Moderately Voted'
        WHEN p.Score > 0 THEN 'Slightly Voted'
        ELSE 'No Votes'
    END as VoteStatus,
    CONCAT(
        'Post #', 
        p.Id, 
        ' created on ', 
        TO_CHAR(p.CreationDate, 'YYYY-MM-DD'),
        ' by ', 
        COALESCE(u.DisplayName, 'Anonymous User')
    ) as PostSummary
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Posts p2 ON p2.Id = p.AcceptedAnswerId
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
WHERE 
    p.PostTypeId IN (1,2)
    AND p.CreationDate >= '2020-01-01'
    AND (
        p.Score > 10 
        OR EXISTS (
            SELECT 1 FROM Comments c 
            WHERE c.PostId = p.Id AND c.Score > 5
        )
    )
    AND (
        p.Tags IS NOT NULL 
        AND p.Tags <> ''
    )
    AND (
        p.Title ILIKE '%sql%' 
        OR EXISTS (
            SELECT 1 FROM Tags t 
            WHERE t.TagName IN ('sql', 'postgresql', 'database') 
            AND p.Tags ILIKE '%' || t.TagName || '%'
        )
    )
    AND (
        p.ViewCount > 0 
        OR p.CommentCount > 0
        OR p.FavoriteCount > 0
    )
    AND (
        p.LastActivityDate >= '2021-01-01'
        OR p.CreationDate >= '2021-01-01'
    )
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory ph2 
        WHERE ph2.PostId = p.Id 
        AND ph2.PostHistoryTypeId IN (12, 13, 10)
        AND ph2.CreationDate > '2020-01-01'
    )
    AND (
        CASE 
            WHEN p.PostTypeId = 1 THEN TRUE
            WHEN p.PostTypeId = 2 THEN EXISTS (
                SELECT 1 FROM Posts pq WHERE pq.Id = p.ParentId AND pq.PostTypeId = 1
            )
            ELSE FALSE
        END
    )
ORDER BY p.CreationDate DESC, p.Score DESC
LIMIT 1000;