WITH q AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.ParentId = p.Id 
           AND a.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id 
           AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id 
           AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT MAX(v.CreationDate) 
         FROM Votes v 
         WHERE v.PostId = p.Id) AS LastVoteDate
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
),
ranked AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerReputation,
        q.AnswerCount,
        q.UpVoteCount,
        q.DownVoteCount,
        q.ViewCount,
        q.Score,
        q.CreationDate,
        q.LastVoteDate,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.CreationDate DESC) AS UserQuestionRank,
        RANK() OVER (ORDER BY (q.UpVoteCount - q.DownVoteCount) DESC) AS GlobalVoteRank,
        CASE 
            WHEN q.AnswerCount = 0 THEN 'Unanswered'
            WHEN q.AnswerCount = 1 THEN 'SingleAnswer'
            ELSE 'MultipleAnswers'
        END AS AnswerStatus,
        COALESCE(b.GoldBadges,0) + COALESCE(b.SilverBadges,0) + COALESCE(b.BronzeBadges,0) AS TotalBadges
    FROM q
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = q.OwnerUserId
),
comment_stats AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 30), '; ') AS SampleComments
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
primary_result AS (
SELECT 
    r.QuestionId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.UpVoteCount,
    r.DownVoteCount,
    r.AnswerStatus,
    r.UserQuestionRank,
    r.GlobalVoteRank,
    r.TotalBadges,
    cs.CommentCount,
    cs.LastCommentDate,
    cs.SampleComments,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = r.QuestionId 
              AND pl.LinkTypeId = 3 
              AND pl.RelatedPostId IS NOT NULL
        ) THEN 1 ELSE 0 
    END AS IsDuplicateLinked,
    COALESCE(
        (SELECT ph.Text
         FROM PostHistory ph 
         WHERE ph.PostId = r.QuestionId 
           AND ph.PostHistoryTypeId = 10 
         ORDER BY ph.CreationDate DESC
         LIMIT 1), 
        'N/A') AS LastCloseReason
FROM ranked r
LEFT JOIN comment_stats cs ON cs.PostId = r.QuestionId
WHERE r.UserQuestionRank <= 5
  AND r.TotalBadges > 2
  AND (r.AnswerCount = 0 OR r.AnswerCount >= 3)
),

secondary_result AS (
SELECT 
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.UpVoteCount,
    q.DownVoteCount,
    CASE WHEN q.AnswerCount = 0 THEN 'Unanswered' ELSE 'Answered' END AS AnswerStatus,
    CAST(NULL AS integer) AS UserQuestionRank,
    CAST(NULL AS integer) AS GlobalVoteRank,
    CAST(NULL AS integer) AS TotalBadges,
    CAST(NULL AS integer) AS CommentCount,
    CAST(NULL AS timestamp) AS LastCommentDate,
    CAST(NULL AS text) AS SampleComments,
    CAST(NULL AS integer) AS IsDuplicateLinked,
    CAST(NULL AS text) AS LastCloseReason
FROM q
WHERE q.Score > 50
  AND q.ViewCount > 1000
  AND q.Tags LIKE '%<c%>'   -- contains the tag <c>
)

SELECT * FROM primary_result
UNION ALL
SELECT * FROM secondary_result
ORDER BY CreationDate DESC;