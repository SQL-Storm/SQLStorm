-- {"query": "3077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1078} 
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p1.Id) FILTER (WHERE p1.PostTypeId = 1) AS QuestionCount,
        COUNT(p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswerCount,
        AVG(COALESCE(p1.Score, 0)) AS AvgQuestionScore,
        AVG(COALESCE(p2.Score, 0)) AS AvgAnswerScore,
        SUM(CASE WHEN v1.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v1.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven
    FROM
        Users u
        LEFT JOIN Posts p1 ON p1.OwnerUserId = u.Id AND p1.PostTypeId = 1
        LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id AND p2.PostTypeId = 2
        LEFT JOIN Votes v1 ON v1.UserId = u.Id AND v1.PostId IN (p1.Id, p2.Id)
    GROUP BY u.Id, u.DisplayName
),
PostHistoryRecent AS (
    SELECT
        ph.PostId,
        ph.UserId AS LastEditorId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
        PostHistory ph
        INNER JOIN PostTypes pt ON pt.Id = (SELECT PostTypeId FROM Posts WHERE Id = ph.PostId)
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
),
PostsTaggedQuestions AS (
    SELECT
        p.Id AS PostId,
        t.TagName,
        p.CreationDate
    FROM
        Posts p
        LEFT JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON TRUE
    WHERE p.PostTypeId = 1
),
TopQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        c.CloseReasonId,
        c.ClosedDate,
        a.AnswerCount,
        v.VoteTypeId,
        v.CreationDate AS VoteDate
    FROM
        Posts p
        LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
        LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
        LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        LEFT JOIN PostHistory c ON c.PostId = p.Id AND c.PostHistoryTypeId = 10
    WHERE
        p.PostTypeId = 1
),
ComplexPredicate AS (
    SELECT
        su.UserId,
        su.DisplayName,
        ROUND(AVG(su.AvgQuestionScore), 2) AS AvgQuestionScore,
        ROUND(AVG(su.AvgAnswerScore), 2) AS AvgAnswerScore,
        SUM(su.TotalUpVotesGiven) AS TotalUpVotes,
        SUM(su.TotalDownVotesGiven) AS TotalDownVotes,
        COUNT(DISTINCT pt.PostId) AS TaggedQuestionsCount
    FROM
        UserPostStats su
        LEFT JOIN PostsTaggedQuestions pt ON su.UserId = pt.PostId % 1000  -- arbitrary join condition for diversity
    GROUP BY su.UserId, su.DisplayName
),
FinalResults AS (
    SELECT
        cp.UserId,
        cp.DisplayName,
        cp.AvgQuestionScore,
        cp.AvgAnswerScore,
        cp.TotalUpVotes,
        cp.TotalDownVotes,
        cp.TaggedQuestionsCount,
        MAX(ph.EditDate) FILTER (WHERE ph.rn = 1) AS LastEditDate,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS AllTags
    FROM
        ComplexPredicate cp
        LEFT JOIN PostHistoryRecent ph ON cp.UserId = ph.UserId AND ph.rn = 1
        LEFT JOIN PostsTaggedQuestions t ON t.PostId = cp.UserId
    GROUP BY cp.UserId, cp.DisplayName, cp.AvgQuestionScore, cp.AvgAnswerScore, cp.TotalUpVotes, cp.TotalDownVotes, cp.TaggedQuestionsCount
)
SELECT
    fr.UserId,
    fr.DisplayName,
    fr.AvgQuestionScore,
    fr.AvgAnswerScore,
    fr.TotalUpVotes,
    fr.TotalDownVotes,
    fr.TaggedQuestionsCount,
    fr.LastEditDate,
    fr.AllTags
FROM
    FinalResults fr
WHERE
    fr.AvgQuestionScore > 0 AND fr.TotalUpVotes > 5
ORDER BY
    fr.TotalUpVotes DESC, fr.AvgQuestionScore DESC
LIMIT 100;