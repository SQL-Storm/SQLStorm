WITH user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags) - 2) AS PrimaryTag,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        NULLIF(STRING_AGG(bn.Name, ', ' ORDER BY bn.MaxDate DESC), '') AS TagBadges
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId 
        AND p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
    LEFT JOIN (
        SELECT UserId, Name, MAX(Date) AS MaxDate
        FROM Badges
        GROUP BY UserId, Name
    ) bn ON u.Id = bn.UserId
    WHERE u.Reputation > 1000
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags) - 2)
    HAVING COUNT(DISTINCT p.Id) >= 5
),
answer_quality AS (
    SELECT 
        a.OwnerUserId,
        a.ParentId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.CreationDate AS QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600 AS HoursToAnswer,
        CASE 
            WHEN a.Id = q.AcceptedAnswerId THEN 1 
            ELSE 0 
        END AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC) AS AnswerRank,
        DENSE_RANK() OVER (PARTITION BY q.Id ORDER BY a.CreationDate) AS ResponseOrder,
        LAG(a.Score, 1, 0) OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate) AS PrevAnswerScore,
        LEAD(a.CreationDate) OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate) AS NextAnswerDate
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
        AND q.ClosedDate IS NULL
),
edit_patterns AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5,8) THEN ph.Id END) AS BodyEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (3,6,9) THEN ph.Id END) AS TagEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
        COALESCE(
            NULLIF(TRIM(BOTH ' ' FROM REGEXP_REPLACE(ph.Text, '[^A-Za-z0-9\s]', '', 'g')), ''),
            'No text'
        ) AS CleanedText,
        STRING_AGG(
            CASE 
                WHEN ph.UserDisplayName IS NOT NULL THEN UPPER(SUBSTRING(ph.UserDisplayName FROM 1 FOR 1)) || LOWER(SUBSTRING(ph.UserDisplayName FROM 2))
                ELSE NULL
            END, 
            ' -> ' 
            ORDER BY ph.CreationDate
        ) AS EditorChain
    FROM PostHistory ph
    WHERE ph.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY ph.PostId, ph.UserId, ph.Text
),
comment_sentiment AS (
    SELECT 
        c.PostId,
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(CHAR_LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%thank%' OR LOWER(c.Text) LIKE '%great%' OR LOWER(c.Text) LIKE '%awesome%' THEN 1 ELSE 0 END) AS PositiveComments,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%wrong%' OR LOWER(c.Text) LIKE '%bad%' OR LOWER(c.Text) LIKE '%terrible%' THEN 1 ELSE 0 END) AS NegativeComments,
        MAX(c.Score) AS MaxCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.PostId, c.UserId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.PrimaryTag,
    ue.QuestionCount,
    ROUND(CAST(ue.AvgQuestionScore AS numeric), 2) AS AvgQuestionScore,
    ue.MedianScore,
    COALESCE(ue.TagBadges, 'No tag badges') AS TagBadges,
    COUNT(DISTINCT aq.AnswerId) AS TotalAnswers,
    SUM(aq.IsAccepted) AS AcceptedAnswers,
    ROUND(CAST(AVG(CASE WHEN aq.AnswerRank <= 10 THEN aq.AnswerScore END) AS numeric), 2) AS Top10AnswerAvgScore,
    ROUND(CAST(AVG(CASE WHEN aq.IsAccepted = 1 AND aq.HoursToAnswer < 168 THEN aq.HoursToAnswer END) AS numeric), 2) AS AvgHoursToAcceptedAnswer,
    COALESCE(SUM(ep.BodyEdits), 0) + COALESCE(SUM(ep.TagEdits), 0) AS TotalEdits,
    STRING_AGG(DISTINCT ep.CloseReason, '; ') AS CloseReasons,
    SUM(cs.PositiveComments) - SUM(cs.NegativeComments) AS CommentSentimentScore,
    CASE 
        WHEN ue.Reputation >= 10000 AND COUNT(DISTINCT aq.AnswerId) >= 50 THEN 'Expert Contributor'
        WHEN ue.Reputation >= 5000 OR SUM(aq.IsAccepted) >= 10 THEN 'Active Helper'
        WHEN ue.QuestionCount > COUNT(DISTINCT aq.AnswerId) THEN 'Question Focused'
        ELSE 'Balanced Participant'
    END AS UserCategory,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY aq.AnswerScore - COALESCE(aq.PrevAnswerScore, 0)) AS ScoreImprovementP75
FROM user_expertise ue
LEFT JOIN answer_quality aq ON ue.UserId = aq.OwnerUserId
LEFT JOIN edit_patterns ep ON ue.UserId = ep.UserId
LEFT JOIN comment_sentiment cs ON ue.UserId = cs.UserId
WHERE ue.Reputation > (
    SELECT AVG(u2.Reputation) 
    FROM Users u2
    WHERE u2.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '3 years'
)
    OR EXISTS (
        SELECT 1 
        FROM Badges b2 
        WHERE b2.UserId = ue.UserId 
            AND b2.Class = 1
    )
GROUP BY 
    ue.UserId,
    ue.DisplayName, 
    ue.Reputation, 
    ue.PrimaryTag, 
    ue.QuestionCount, 
    ue.AvgQuestionScore, 
    ue.MedianScore,
    ue.TagBadges
HAVING COUNT(DISTINCT aq.AnswerId) > 0 
    OR ue.QuestionCount >= 10
ORDER BY 
    ue.Reputation DESC,
    SUM(aq.IsAccepted) DESC,
    ue.AvgQuestionScore DESC
LIMIT 100;