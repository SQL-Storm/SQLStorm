-- {"query": "7041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2604} 
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
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        ELSE pt.Name 
    END as PostType,
    COALESCE(p.Tags, '') as Tags,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountActual,
    CASE 
        WHEN p.PostTypeId = 1 THEN 
            (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.DeletedDate IS NULL)
        ELSE 0 
    END as AnswerCountActual,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
            (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId)
        ELSE 0 
    END as AcceptedAnswerScore,
    (SELECT STRING_AGG(CONCAT(b.Name, ' (', b.Date, ')'), ', ') 
     FROM Badges b 
     WHERE b.UserId = p.OwnerUserId AND b.TagBased = 0
     ORDER BY b.Date DESC) as UserBadges,
    ARRAY_TO_STRING(
        (SELECT ARRAY_AGG(t.TagName ORDER BY t.Count DESC) 
         FROM Tags t 
         WHERE t.TagName = ANY(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '<>')) 
           AND t.Count > 1000), 
        ', '
    ) as PopularTags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
    RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
    NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreDecile,
    LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
    LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as AvgScore3Posts,
    (SELECT COUNT(*) FROM PostHistory ph 
     WHERE ph.PostId = p.Id 
       AND ph.PostHistoryTypeId IN (4,5,6,24) 
       AND ph.CreationDate > p.CreationDate) as EditCount,
    CASE 
        WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 
            (SELECT Name FROM CloseReasonTypes crt WHERE crt.Id = 
                (SELECT CAST(SUBSTRING(ph.Comment FROM 2 FOR LENGTH(ph.Comment)-2) AS INTEGER) 
                 FROM PostHistory ph 
                 WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 
                 ORDER BY ph.CreationDate DESC LIMIT 1))
        ELSE 'Open'
    END as CloseReason,
    COALESCE(
        (SELECT STRING_AGG(
            CONCAT(h.PostHistoryTypeId, ':', 
                   CASE WHEN h.Comment IS NOT NULL THEN SUBSTRING(h.Comment, 1, 50) ELSE 'No comment' END,
                   ' @ ', h.CreationDate), 
            ' | ') 
         FROM PostHistory h 
         WHERE h.PostId = p.Id 
           AND h.CreationDate > p.CreationDate
           AND h.PostHistoryTypeId IN (10,11,12,13,14,15,19,20)
         ORDER BY h.CreationDate ASC), 
        'No major edits'
    ) as RecentHistory,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) 
        THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3)
        ELSE 0 
    END as DuplicateLinks,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) 
        THEN (SELECT STRING_AGG(CONCAT('Link to: ', p2.Title, ' (', p2.Id, ')'), '; ') 
              FROM PostLinks pl 
              JOIN Posts p2 ON pl.RelatedPostId = p2.Id
              WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1)
        ELSE ''
    END as RelatedLinks,
    EXTRACT(YEAR FROM p.CreationDate) as CreationYear,
    EXTRACT(MONTH FROM p.CreationDate) as CreationMonth,
    CASE 
        WHEN p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '7 days') THEN 'Recent'
        WHEN p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '30 days') THEN 'Last Month'
        WHEN p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '90 days') THEN 'Last Quarter'
        ELSE 'Old'
    END as Recency,
    CASE 
        WHEN p.Score > 100 AND p.ViewCount > 1000 THEN 'High Impact'
        WHEN p.Score > 50 AND p.ViewCount > 500 THEN 'Medium Impact'
        WHEN p.Score > 10 AND p.ViewCount > 100 THEN 'Low Impact'
        ELSE 'Minimal'
    END as ImpactCategory,
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.OwnerUserId = p.OwnerUserId 
       AND p2.PostTypeId = 1 
       AND p2.CreationDate < p.CreationDate) as PreviousQuestions,
    (SELECT AVG(p3.Score) FROM Posts p3 
     WHERE p3.OwnerUserId = p.OwnerUserId 
       AND p3.PostTypeId = 1 
       AND p3.CreationDate < p.CreationDate) as AvgScorePrevious,
    (CASE WHEN p.Score > (SELECT AVG(p4.Score) FROM Posts p4 WHERE p4.OwnerUserId = p.OwnerUserId AND p4.PostTypeId = 1) 
          THEN 1 ELSE 0 END) as AboveAverage,
    NULLIF(p.ViewCount, 0) / NULLIF(p.Score, 0) as ViewsPerScoreRatio,
    NULLIF(p.CommentCount, 0) / NULLIF(p.AnswerCount, 0) as CommentsPerAnswerRatio,
    CASE 
        WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 5 THEN 
            (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '<', ''))) / 2
        ELSE 0 
    END as TagCount,
    DATEDIFF('days', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
    CASE 
        WHEN p.LastEditDate IS NOT NULL THEN DATEDIFF('days', p.CreationDate, p.LastEditDate)
        ELSE 0 
    END as DaysSinceLastEdit,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
    CASE WHEN u.Views IS NULL THEN 0 ELSE u.Views END as UserViews,
    CASE WHEN u.DownVotes IS NULL THEN 0 ELSE u.DownVotes END as UserDownVotes,
    CASE WHEN p.OwnerDisplayName IS NULL THEN u.DisplayName ELSE p.OwnerDisplayName END as AuthorName,
    CASE 
        WHEN p.OwnerUserId IS NULL THEN 'Community Wiki'
        WHEN p.OwnerUserId = -1 THEN 'Community-owned'
        ELSE 'User-owned'
    END as OwnershipStatus,
    CASE 
        WHEN (p.Score > 10 OR p.AnswerCount > 5 OR p.CommentCount > 20 OR p.FavoriteCount > 10) 
        THEN 'High Engagement'
        ELSE 'Standard'
    END as EngagementLevel,
    (SELECT STRING_AGG(CONCAT('v', v.VoteTypeId, ':', CASE WHEN v.UserId IS NOT NULL THEN 'User' ELSE 'System' END), ', ')
     FROM Votes v 
     WHERE v.PostId = p.Id 
       AND v.VoteTypeId IN (1,2,3,4)) as VoteTypes,
    (SELECT STRING_AGG(CONCAT('h', ph.PostHistoryTypeId, ':', ph.CreationDate), '; ')
     FROM PostHistory ph 
     WHERE ph.PostId = p.Id 
       AND ph.PostHistoryTypeId IN (1,2,3,4,5,6) 
       AND ph.CreationDate > p.CreationDate) as InitialHistory,
    (SELECT MIN(ph.CreationDate) 
     FROM PostHistory ph 
     WHERE ph.PostId = p.Id) as FirstHistoryDate,
    (SELECT MAX(ph.CreationDate) 
     FROM PostHistory ph 
     WHERE ph.PostId = p.Id) as LastHistoryDate,
    (SELECT COUNT(DISTINCT ph.UserId) 
     FROM PostHistory ph 
     WHERE ph.PostId = p.Id) as UniqueEditors,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 1) as AcceptVotes,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 5) as FavoriteVotes,
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId IN (10,11)) as CloseOpenEvents,
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (8,9)) as BountyVotes,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AnswerCountAll,
    CASE 
        WHEN p.PostTypeId = 1 THEN 
            (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.Score > 10)
        ELSE 0 
    END as HighScoringAnswers
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.CreationDate >= '2020-01-01'
  AND p.PostTypeId IN (1, 2)
  AND (p.Title IS NOT NULL OR p.Body IS NOT NULL)
  AND (p.ViewCount IS NOT NULL OR p.Score IS NOT NULL)
  AND (
    CASE 
      WHEN p.Score > 100 THEN TRUE
      WHEN p.ViewCount > 1000 THEN TRUE
      WHEN p.AnswerCount > 5 THEN TRUE
      WHEN p.CommentCount > 20 THEN TRUE
      ELSE p.FavoriteCount > 10 
    END
  )
  AND p.Id NOT IN (
    SELECT DISTINCT ph.PostId 
    FROM PostHistory ph 
    WHERE ph.PostHistoryTypeId IN (12,13) 
      AND ph.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
  )
  AND p.Id IN (
    SELECT ph.PostId 
    FROM PostHistory ph 
    WHERE ph.PostHistoryTypeId IN (1,2,3,4,5,6,24) 
      AND ph.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    INTERSECT
    SELECT p2.Id 
    FROM Posts p2 
    WHERE p2.Score > 50 AND p2.ViewCount > 500
  )
  AND CASE 
    WHEN p.Tags IS NOT NULL THEN 
      (SELECT COUNT(*) FROM Tags WHERE TagName = ANY(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '<>')) AND Count > 5000) > 0
    ELSE FALSE 
  END
ORDER BY p.CreationDate DESC, p.Score DESC, p.ViewCount DESC
LIMIT 5000;