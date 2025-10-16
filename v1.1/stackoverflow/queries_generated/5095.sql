-- {"query": "5095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1072} 
WITH RecentQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.AnswerCount,0) AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
UserRecentQuestions AS (
    SELECT 
        rq.*,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.Location
    FROM RecentQuestions rq
    INNER JOIN Users u ON rq.OwnerUserId = u.Id
    WHERE rq.rn <= 5
),
TopAnswersPerQuestion AS (
    SELECT
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.Score IS NOT NULL
),
AcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.AcceptedAnswerId
    FROM Posts q
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),
AnswererBadges AS (
    SELECT
        a.AnswerOwnerId,
        COUNT(DISTINCT b.Id) AS NumBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM TopAnswersPerQuestion a
    JOIN Badges b ON a.AnswerOwnerId = b.UserId
    WHERE a.rn = 1
    GROUP BY a.AnswerOwnerId
),
QuestionCommentsAgg AS (
    SELECT
        c.PostId,
        COUNT(*) AS NumComments,
        MAX(CASE WHEN c.Score IS NULL THEN 0 ELSE c.Score END) AS MaxCommentScore,
        SUM(CASE WHEN c.Text ILIKE '%thank%' THEN 1 ELSE 0 END) AS ThankComments
    FROM Comments c
    GROUP BY c.PostId
),
TagExtract AS (
    SELECT
        q.PostId,
        UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
    FROM UserRecentQuestions q
    WHERE q.Tags IS NOT NULL
),
PopularTags AS (
    SELECT
        t.TagName,
        COUNT(*) AS NumQuestions
    FROM TagExtract t
    GROUP BY t.TagName
    HAVING COUNT(*) > 1
),
ClosedReasons AS (
    SELECT
        ph.PostId,
        cr.Name AS CloseReason
    FROM PostHistory ph
    JOIN CloseReasonTypes cr ON cr.Id::varchar = ph.Comment
    WHERE ph.PostHistoryTypeId = 10 -- post closed
)
SELECT
    urq.PostId,
    urq.Title,
    urq.UserDisplayName,
    urq.Reputation,
    urq.Location,
    urq.CreationDate AS QuestionDate,
    urq.AnswerCount,
    ARRAY(
        SELECT ta.AnswerId
        FROM TopAnswersPerQuestion ta
        WHERE ta.QuestionId = urq.PostId AND ta.rn = 1
    ) AS TopAnswerIds,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM AcceptedAnswers aa
            WHERE aa.QuestionId = urq.PostId AND aa.AcceptedAnswerId IS NOT NULL
        )
        THEN 'Accepted'
        ELSE 'Unaccepted'
    END AS AcceptedStatus,
    qb.NumComments,
    qb.MaxCommentScore,
    qb.ThankComments,
    ab.NumBadges AS TopAnswererBadges,
    ab.BadgeNames,
    COALESCE(clr.CloseReason, 'Open') AS QuestionStatus,
    ARRAY(
        SELECT pt.TagName
        FROM PopularTags pt
        JOIN TagExtract te ON pt.TagName = te.TagName AND te.PostId = urq.PostId
    ) AS PopularTags,
    (
        SELECT COUNT(DISTINCT v.UserId)
        FROM Votes v
        WHERE v.PostId = urq.PostId AND v.VoteTypeId = 2
    ) AS UniqueUpvoters,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.RelatedPostId = urq.PostId 
          AND pl.LinkTypeId IN (1,3)
    ) AS TimesLinkedTo
FROM UserRecentQuestions urq
LEFT JOIN TopAnswersPerQuestion tapq 
    ON tapq.QuestionId = urq.PostId AND tapq.rn = 1
LEFT JOIN AnswererBadges ab ON ab.AnswerOwnerId = tapq.AnswerOwnerId
LEFT JOIN QuestionCommentsAgg qb ON qb.PostId = urq.PostId
LEFT JOIN ClosedReasons clr ON clr.PostId = urq.PostId
ORDER BY urq.UserDisplayName ASC, urq.CreationDate DESC;