WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS QuestionCreationDate,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
),
AnswerDetails AS (
    SELECT
        ans.Id AS AnswerId,
        ans.ParentId AS QuestionId,
        ans.OwnerUserId AS AnswerOwnerUserId,
        ans.CreationDate AS AnswerCreationDate,
        ans.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY ans.ParentId ORDER BY ans.Score DESC, ans.CreationDate ASC) AS answer_rank
    FROM Posts ans
    WHERE ans.PostTypeId = 2
),
TopAnswers AS (
    SELECT
        ad.QuestionId,
        ad.AnswerId,
        ad.AnswerOwnerUserId,
        u_ans.DisplayName AS AnswerOwnerDisplayName,
        ad.AnswerCreationDate,
        ad.AnswerScore
    FROM AnswerDetails ad
    JOIN Users u_ans ON ad.AnswerOwnerUserId = u_ans.Id
    WHERE ad.answer_rank <= 3
),
QuestionWithAnswers AS (
    SELECT
        rq.QuestionId,
        rq.QuestionTitle,
        rq.OwnerUserId,
        rq.OwnerDisplayName,
        rq.QuestionCreationDate,
        ta.AnswerId,
        ta.AnswerOwnerUserId,
        ta.AnswerOwnerDisplayName,
        ta.AnswerCreationDate,
        ta.AnswerScore,
        rq.rn
    FROM RecentQuestions rq
    LEFT JOIN TopAnswers ta ON rq.QuestionId = ta.QuestionId
    WHERE rq.rn <= 50
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS DownVotesGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT p.Id) AS PostsCount
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10 OR COUNT(DISTINCT c.Id) > 50
)
SELECT
    qwa.QuestionTitle,
    qwa.OwnerDisplayName AS QuestionAuthor,
    qwa.QuestionCreationDate,
    qwa.AnswerOwnerDisplayName AS BestAnswerAuthor,
    qwa.AnswerScore AS BestAnswerScore,
    qwa.AnswerCreationDate AS BestAnswerDate,
    ue.DisplayName AS EngagedUser,
    ue.UpVotesGiven,
    ue.DownVotesGiven,
    ue.CommentsMade,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    CASE
        WHEN qwa.AnswerScore IS NULL THEN 'No good answer'
        WHEN qwa.AnswerScore >= 50 THEN 'Highly Valued Answer'
        WHEN qwa.AnswerScore >= 10 THEN 'Good Answer'
        ELSE 'Average Answer'
    END AS AnswerQualityCategory,
    CAST(qwa.QuestionCreationDate AS DATE) AS QuestionDate,
    CHAR_LENGTH(qwa.QuestionTitle) AS TitleLength,
    COALESCE(u_q.Location, 'Unknown Location') AS QuestionerLocation,
    CASE WHEN qwa.OwnerUserId = qwa.AnswerOwnerUserId THEN 'Same User' ELSE 'Different Users' END AS OwnerAnswererRelation,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = qwa.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinks,
    ue.UserId AS EngagedUserId,
    qwa.QuestionId
FROM QuestionWithAnswers qwa
FULL OUTER JOIN UserEngagement ue
  ON qwa.OwnerUserId = ue.UserId
LEFT JOIN Users u_q ON qwa.OwnerUserId = u_q.Id
WHERE qwa.QuestionId IS NOT NULL OR ue.UserId IS NOT NULL
GROUP BY
    qwa.QuestionTitle,
    qwa.OwnerDisplayName,
    qwa.QuestionCreationDate,
    qwa.AnswerOwnerDisplayName,
    qwa.AnswerScore,
    qwa.AnswerCreationDate,
    ue.DisplayName,
    ue.UpVotesGiven,
    ue.DownVotesGiven,
    ue.CommentsMade,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    qwa.AnswerOwnerUserId,
    qwa.OwnerUserId,
    qwa.QuestionId,
    CAST(qwa.QuestionCreationDate AS DATE),
    CHAR_LENGTH(qwa.QuestionTitle),
    u_q.Location,
    ue.UserId
ORDER BY qwa.QuestionCreationDate DESC, ue.UserId DESC
LIMIT 100;