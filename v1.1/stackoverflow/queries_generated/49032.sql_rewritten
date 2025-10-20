-- {"query": "49032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1658} 
WITH QuestionCandidates AS (
    -- Identify initial question candidates based on post type, creation date, and specific tags.
    -- The tags 'sql' or 'performance' are parsed from the Tags string.
    SELECT
        p.Id AS QuestionId,
        p.CreationDate AS QuestionCreationDate,
        p.AcceptedAnswerId,
        p.OwnerUserId AS QuestionOwnerUserId,
        p.Tags,
        p.Score AS QuestionScore,
        p.ViewCount
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate >= '2018-01-01' -- Filter for recent activity (post 2018)
        AND p.AcceptedAnswerId IS NOT NULL -- Must have an accepted answer
        AND EXISTS (
            SELECT 1
            FROM UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag_name
            WHERE tag_name IN ('sql', 'performance')
        )
),
QuestionsWithHistoryAndVotes AS (
    -- Further refine question candidates by requiring a minimum number of edits and upvotes,
    -- and a high view count, indicating significant engagement.
    SELECT
        qc.QuestionId,
        qc.QuestionCreationDate,
        qc.AcceptedAnswerId,
        qc.QuestionOwnerUserId,
        qc.Tags,
        qc.QuestionScore,
        qc.ViewCount
    FROM
        QuestionCandidates qc
    INNER JOIN (
        -- Subquery to count distinct edit revisions for each post
        SELECT
            ph.PostId,
            COUNT(DISTINCT ph.RevisionGUID) AS EditCount
        FROM
            PostHistory ph
        WHERE
            ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        GROUP BY
            ph.PostId
        HAVING
            COUNT(DISTINCT ph.RevisionGUID) >= 3 -- At least 3 distinct edits
    ) AS EditSummary ON qc.QuestionId = EditSummary.PostId
    INNER JOIN (
        -- Subquery to count upvotes for each post
        SELECT
            v.PostId,
            COUNT(v.Id) AS UpVoteCount
        FROM
            Votes v
        WHERE
            v.VoteTypeId = 2 -- UpMod (upvote)
        GROUP BY
            v.PostId
        HAVING
            COUNT(v.Id) > 10 -- More than 10 upvotes
    ) AS VoteSummary ON qc.QuestionId = VoteSummary.PostId
    WHERE
        qc.ViewCount > 1000 -- Questions must be highly viewed
),
LinkedAndPopularQuestions AS (
    -- Add another layer of complexity by ensuring these questions are linked to other popular questions.
    SELECT
        qwhv.*,
        pl.RelatedPostId AS LinkedQuestionId
    FROM
        QuestionsWithHistoryAndVotes qwhv
    INNER JOIN
        PostLinks pl ON qwhv.QuestionId = pl.PostId -- qwhv.QuestionId links to pl.RelatedPostId
    INNER JOIN
        Posts related_p ON pl.RelatedPostId = related_p.Id -- The related post details
    WHERE
        related_p.PostTypeId = 1 -- Ensure the linked post is also a question
        AND related_p.ViewCount > 500 -- The linked question itself must be popular
),
AcceptedAnswersDetail AS (
    -- Retrieve details of the accepted answers for the filtered, linked, and popular questions.
    SELECT
        lapq.QuestionId,
        lapq.QuestionCreationDate,
        lapq.AcceptedAnswerId,
        lapq.QuestionOwnerUserId,
        lapq.Tags,
        lapq.QuestionScore,
        lapq.ViewCount,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore
    FROM
        LinkedAndPopularQuestions lapq
    INNER JOIN
        Posts a ON lapq.AcceptedAnswerId = a.Id
    WHERE
        a.PostTypeId = 2 -- Ensure it's an answer
        AND a.OwnerUserId IS NOT NULL -- The answer must have an owner
),
QuarterlyUserPerformance AS (
    -- Aggregate performance metrics for each user per quarter based on their accepted answers.
    -- Includes total answer score, average time to acceptance, and unique tags contributed to.
    SELECT
        DATE_TRUNC('quarter', aad.AnswerCreationDate) AS Quarter,
        aad.AnswerOwnerUserId AS UserId,
        SUM(aad.AnswerScore) AS TotalAnswerScore,
        AVG(EXTRACT(EPOCH FROM (aad.AnswerCreationDate - aad.QuestionCreationDate))) AS AvgTimeToAcceptInSeconds,
        COUNT(DISTINCT t.tag) AS UniqueTagsContributedTo -- Count unique tags from all questions where this user provided an accepted answer in the quarter
    FROM
        AcceptedAnswersDetail aad,
        UNNEST(string_to_array(SUBSTRING(aad.Tags, 2, LENGTH(aad.Tags) - 2), '><')) AS t(tag)
    GROUP BY
        DATE_TRUNC('quarter', aad.AnswerCreationDate),
        aad.AnswerOwnerUserId
    HAVING
        SUM(aad.AnswerScore) > 0 -- Only consider users with a positive answer score
),
RankedQuarterlyUsers AS (
    -- Rank users within each quarter based on their total answer score.
    SELECT
        qap.Quarter,
        qap.UserId,
        qap.TotalAnswerScore,
        qap.AvgTimeToAcceptInSeconds,
        qap.UniqueTagsContributedTo,
        ROW_NUMBER() OVER (PARTITION BY qap.Quarter ORDER BY qap.TotalAnswerScore DESC) AS rn
    FROM
        QuarterlyUserPerformance qap
)
-- Final selection: Retrieve details for the top 5 ranked users per quarter,
-- including user reputation, vote counts, and badge information.
SELECT
    u.DisplayName,
    rqu.Quarter,
    rqu.TotalAnswerScore,
    rqu.AvgTimeToAcceptInSeconds,
    rqu.UniqueTagsContributedTo,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    MAX(b.Date) AS LatestBadgeDate
FROM
    RankedQuarterlyUsers rqu
INNER JOIN
    Users u ON rqu.UserId = u.Id
LEFT JOIN
    Badges b ON u.Id = b.UserId -- Join with Badges to get user's badge count and latest badge
WHERE
    rqu.rn <= 5 -- Select only the top 5 users per quarter
GROUP BY
    u.DisplayName, rqu.Quarter, rqu.TotalAnswerScore, rqu.AvgTimeToAcceptInSeconds, rqu.UniqueTagsContributedTo,
    u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
ORDER BY
    rqu.Quarter DESC, rqu.TotalAnswerScore DESC;