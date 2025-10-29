-- {"query": "1062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2488} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT p_q.Id) AS QuestionsPosted,
        COUNT(DISTINCT p_a.Id) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsPosted,
        SUM(CASE WHEN p_q.Score IS NOT NULL THEN p_q.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p_a.Score IS NOT NULL THEN p_a.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM
        Users u
    LEFT JOIN
        Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1 -- Questions
    LEFT JOIN
        Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2 -- Answers
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.Tags,
        (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorsCount, -- Edit Title, Body, Tags
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) AS CloseEvents, -- Post Closed
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11) AS ReopenEvents, -- Post Reopened
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScoreByOwner,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScoreByOwner,
        NTH_VALUE(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS LatestPostScoreByOwner,
        COALESCE(
            p.AcceptedAnswerId,
            (SELECT MIN(pa.Id) FROM Posts pa WHERE pa.ParentId = p.Id AND pa.Score >= 5 ORDER BY pa.CreationDate LIMIT 1) -- Pick a highly-scored answer as "effective accepted" if not explicitly accepted
        ) AS EffectiveAcceptedAnswerId
    FROM
        Posts p
    WHERE p.PostTypeId = 1 -- Only consider questions for this CTE
),
ExplodedTags AS (
    SELECT
        phm.PostId,
        phm.PostScore,
        phm.ViewCount,
        phm.OwnerUserId,
        TRIM(s.tag) AS TagName -- `string_to_array(SUBSTRING(phm.Tags, 2, LENGTH(phm.Tags)-2), '><')` already handles the '<' and '>' characters.
    FROM
        PostHistoricalMetrics phm
    LEFT JOIN LATERAL
        (SELECT unnest(string_to_array(SUBSTRING(phm.Tags, 2, LENGTH(phm.Tags)-2), '><')) AS tag) s ON true
    WHERE
        phm.Tags IS NOT NULL AND LENGTH(phm.Tags) > 2 -- ensure tags are not empty or just "<>"
),
RankedTags AS (
    SELECT
        et.TagName,
        SUM(et.PostScore) AS TotalTagScore,
        SUM(et.ViewCount) AS TotalTagViews,
        COUNT(DISTINCT et.PostId) AS QuestionsWithTag,
        DENSE_RANK() OVER (ORDER BY SUM(et.PostScore) DESC, SUM(et.ViewCount) DESC) AS TagScoreRank
    FROM
        ExplodedTags et
    GROUP BY
        et.TagName
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.LastAccessDate,
    ue.QuestionsPosted,
    ue.AnswersPosted,
    ue.CommentsPosted,
    ue.TotalQuestionScore,
    ue.TotalAnswerScore,
    ue.UpvotesGiven,
    ue.DownvotesGiven,
    phm.PostId,
    phm.PostCreationDate,
    phm.PostScore,
    phm.ViewCount,
    phm.AnswerCount,
    phm.FavoriteCount,
    phm.LastEditDate,
    phm.LastActivityDate,
    phm.ClosedDate,
    phm.Tags,
    phm.UniqueEditorsCount,
    phm.CloseEvents,
    phm.ReopenEvents,
    phm.PreviousPostScoreByOwner,
    phm.NextPostScoreByOwner,
    phm.LatestPostScoreByOwner,
    -- PostgreSQL specific for DATEDIFF:
    EXTRACT(EPOCH FROM (
        (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.Id = phm.EffectiveAcceptedAnswerId) - phm.PostCreationDate
    )) / 3600 AS TimeToAcceptAnswerHours,
    (
        SELECT
            STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC)
        FROM
            Badges b
        WHERE
            b.UserId = ue.UserId
            AND b.Class = 1 -- Gold badges only
            AND EXISTS (
                SELECT 1
                FROM RankedTags rt_sub
                WHERE rt_sub.TagName ILIKE '%' || b.Name || '%' -- Correlated subquery: badge name partially matches a top tag
                AND rt_sub.TagScoreRank <= 10
            )
    ) AS TopGoldBadgesRelatedToTopTags,
    rt.TagName AS TopContributingTag,
    rt.TotalTagScore,
    rt.TotalTagViews,
    rt.QuestionsWithTag,
    rt.TagScoreRank,
    CASE
        WHEN phm.CloseEvents > 0 AND phm.ReopenEvents > 0 THEN 'Closed & Reopened'
        WHEN phm.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN phm.AnswerCount > 5 AND phm.PostScore > 50 THEN 'High Engagement'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    phm.PostScore * (1.0 + COALESCE(phm.FavoriteCount, 0) / 10.0) AS WeightedPostScore,
    NULLIF(phm.ViewCount, 0)::numeric / NULLIF(phm.AnswerCount, 0) AS ViewsPerAnswerRatio, -- Cast to numeric for float division
    (
        SELECT
            LOWER(SUBSTRING(c.Text, 1, 50))
        FROM
            Comments c
        WHERE
            c.PostId = phm.PostId
            AND c.Score = (SELECT MAX(c2.Score) FROM Comments c2 WHERE c2.PostId = phm.PostId) -- Correlated subquery for max score comment
        ORDER BY c.CreationDate DESC, c.Id DESC -- Add Id for tie-breaking
        LIMIT 1
    ) AS TopCommentExcerpt
FROM
    UserEngagement ue
JOIN
    PostHistoricalMetrics phm ON ue.UserId = phm.OwnerUserId
LEFT JOIN
    ExplodedTags et_main ON phm.PostId = et_main.PostId
LEFT JOIN
    RankedTags rt ON et_main.TagName = rt.TagName AND rt.TagScoreRank <= 5 -- Only consider top 5 ranked tags for the user's posts
WHERE
    ue.Reputation > 5000
    AND ue.LastAccessDate >= (CURRENT_DATE - INTERVAL '6 months') -- Active users in last 6 months
    AND phm.PostTypeId = 1 -- Focus on questions
    AND phm.PostScore > 10
    AND (phm.CloseEvents > 0 OR phm.UniqueEditorsCount > 2) -- Posts that had history or multiple editors
    AND NOT EXISTS (
        SELECT 1 FROM Badges b_sub WHERE b_sub.UserId = ue.UserId AND b_sub.Name = 'Disciplined' AND b_sub.TagBased = FALSE
    ) -- Non-Correlated subquery in WHERE: filter out users with a specific named badge
    AND phm.PostCreationDate > (CURRENT_DATE - INTERVAL '3 year') -- Posts from the last 3 years
GROUP BY -- Extensive GROUP BY to ensure each row in the result is unique based on user-post-tag combination
    ue.UserId, ue.DisplayName, ue.Reputation, ue.UserCreationDate, ue.LastAccessDate,
    ue.QuestionsPosted, ue.AnswersPosted, ue.CommentsPosted, ue.TotalQuestionScore,
    ue.TotalAnswerScore, ue.UpvotesGiven, ue.DownvotesGiven, phm.PostId, phm.PostCreationDate,
    phm.PostScore, phm.ViewCount, phm.AnswerCount, phm.FavoriteCount,
    phm.LastEditDate, phm.LastActivityDate, phm.ClosedDate, phm.Tags,
    phm.UniqueEditorsCount, phm.CloseEvents, phm.ReopenEvents,
    phm.PreviousPostScoreByOwner, phm.NextPostScoreByOwner, phm.LatestPostScoreByOwner,
    phm.EffectiveAcceptedAnswerId, rt.TagName, rt.TotalTagScore, rt.TotalTagViews,
    rt.QuestionsWithTag, rt.TagScoreRank
ORDER BY
    ue.Reputation DESC, WeightedPostScore DESC, TimeToAcceptAnswerHours ASC, ue.UserId, phm.PostId
LIMIT 1000;
