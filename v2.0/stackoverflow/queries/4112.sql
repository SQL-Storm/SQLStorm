WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        u.Reputation AS EditorReputation,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        ph.Comment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
PostEditSummaries AS (
    SELECT
        rpe.PostId,
        MAX(CASE WHEN rpe.rn = 1 THEN rpe.EditorDisplayName ELSE NULL END) AS LatestEditor,
        MAX(CASE WHEN rpe.rn = 1 THEN rpe.EditorReputation ELSE NULL END) AS LatestEditorRep,
        MAX(CASE WHEN rpe.rn = 1 THEN rpe.EditDate ELSE NULL END) AS LastEditDate,
        COUNT(DISTINCT rpe.UserId) AS UniqueEditors,
        SUM(CASE WHEN rpe.EditType = 'Edit Title' THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN rpe.EditType = 'Edit Body' THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN rpe.EditType = 'Edit Tags' THEN 1 ELSE 0 END) AS TagEdits
    FROM RankedPostEdits rpe
    GROUP BY rpe.PostId
),
QuestionAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.OwnerUserId AS QuestionOwnerUserId,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.OwnerUserId AS AnswerOwnerUserId,
        DENSE_RANK() OVER (ORDER BY q.CreationDate) AS QuestionRank
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2 AND q.AcceptedAnswerId IS NOT NULL
),
UserBadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostVoteAnalysis AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
)
SELECT
    qa.QuestionTitle,
    qa.QuestionCreationDate,
    qa.QuestionRank,
    COALESCE(u_q.DisplayName, CAST(qa.QuestionOwnerUserId AS VARCHAR)) AS QuestionOwnerDisplayName,
    COALESCE(ubc_q.GoldBadges, 0) AS QuestionOwnerGoldBadges,
    COALESCE(ubc_q.SilverBadges, 0) AS QuestionOwnerSilverBadges,
    COALESCE(ubc_q.BronzeBadges, 0) AS QuestionOwnerBronzeBadges,
    qa.AnswerCreationDate,
    COALESCE(u_a.DisplayName, CAST(qa.AnswerOwnerUserId AS VARCHAR)) AS AnswerOwnerDisplayName,
    COALESCE(ubc_a.GoldBadges, 0) AS AnswerOwnerGoldBadges,
    COALESCE(ubc_a.SilverBadges, 0) AS AnswerOwnerSilverBadges,
    COALESCE(ubc_a.BronzeBadges, 0) AS AnswerOwnerBronzeBadges,
    pva.UpVotes AS QuestionUpVotes,
    pva.DownVotes AS QuestionDownVotes,
    pva.Favorites AS QuestionFavorites,
    COALESCE(pva_ans.UpVotes, 0) AS AnswerUpVotes,
    COALESCE(pva_ans.DownVotes, 0) AS AnswerDownVotes,
    pes.LastEditDate,
    pes.LatestEditor,
    pes.UniqueEditors,
    pes.TitleEdits,
    pes.BodyEdits,
    pes.TagEdits,
    CASE
        WHEN qa.QuestionOwnerUserId = qa.AnswerOwnerUserId THEN 'Self-Answered'
        WHEN u_q.CreationDate > u_a.CreationDate THEN 'OlderQuestionOwner'
        WHEN u_q.Reputation > u_a.Reputation THEN 'HigherRepQuestionOwner'
        ELSE 'Standard'
    END AS RelationshipCategory,
    'Answer Score: ' || CAST((SELECT SUM(Score) FROM Comments WHERE PostId = qa.AnswerId) AS VARCHAR) || ', Edits: ' || CAST(COALESCE(pes.TitleEdits + pes.BodyEdits + pes.TagEdits, 0) AS VARCHAR) AS AnswerDetails
FROM QuestionAnswers qa
LEFT JOIN Users u_q ON qa.QuestionOwnerUserId = u_q.Id
LEFT JOIN Users u_a ON qa.AnswerOwnerUserId = u_a.Id
LEFT JOIN UserBadgeCounts ubc_q ON qa.QuestionOwnerUserId = ubc_q.UserId
LEFT JOIN UserBadgeCounts ubc_a ON qa.AnswerOwnerUserId = ubc_a.UserId
LEFT JOIN PostVoteAnalysis pva ON qa.QuestionId = pva.PostId
LEFT JOIN PostVoteAnalysis pva_ans ON qa.AnswerId = pva_ans.PostId
LEFT JOIN PostEditSummaries pes ON qa.QuestionId = pes.PostId
WHERE
    qa.QuestionCreationDate BETWEEN DATE '2010-01-01' AND DATE '2012-12-31'
    AND u_q.Reputation > 10000
    AND (u_a.Views IS NULL OR u_a.Views < 5000)
    AND qa.AnswerCreationDate > qa.QuestionCreationDate + INTERVAL '1' HOUR
    AND qa.AnswerOwnerUserId IS NOT NULL
    AND qa.QuestionOwnerUserId IS NOT NULL
GROUP BY
    qa.QuestionTitle,
    qa.QuestionCreationDate,
    qa.QuestionRank,
    COALESCE(u_q.DisplayName, CAST(qa.QuestionOwnerUserId AS VARCHAR)),
    COALESCE(ubc_q.GoldBadges, 0),
    COALESCE(ubc_q.SilverBadges, 0),
    COALESCE(ubc_q.BronzeBadges, 0),
    qa.AnswerCreationDate,
    COALESCE(u_a.DisplayName, CAST(qa.AnswerOwnerUserId AS VARCHAR)),
    COALESCE(ubc_a.GoldBadges, 0),
    COALESCE(ubc_a.SilverBadges, 0),
    COALESCE(ubc_a.BronzeBadges, 0),
    pva.UpVotes,
    pva.DownVotes,
    pva.Favorites,
    COALESCE(pva_ans.UpVotes, 0),
    COALESCE(pva_ans.DownVotes, 0),
    pes.LastEditDate,
    pes.LatestEditor,
    pes.UniqueEditors,
    pes.TitleEdits,
    pes.BodyEdits,
    pes.TagEdits,
    CASE
        WHEN qa.QuestionOwnerUserId = qa.AnswerOwnerUserId THEN 'Self-Answered'
        WHEN u_q.CreationDate > u_a.CreationDate THEN 'OlderQuestionOwner'
        WHEN u_q.Reputation > u_a.Reputation THEN 'HigherRepQuestionOwner'
        ELSE 'Standard'
    END,
    'Answer Score: ' || CAST((SELECT SUM(Score) FROM Comments WHERE PostId = qa.AnswerId) AS VARCHAR) || ', Edits: ' || CAST(COALESCE(pes.TitleEdits + pes.BodyEdits + pes.TagEdits, 0) AS VARCHAR)
HAVING COUNT(qa.AnswerId) > 1
ORDER BY qa.QuestionCreationDate DESC, qa.AnswerCreationDate DESC
LIMIT 100;