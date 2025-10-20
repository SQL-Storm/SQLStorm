-- {"query": "50088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1151} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT q.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsWritten,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM
        Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.Id > 0
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserTagContributions AS (
    SELECT
        OwnerUserId,
        Tag,
        TagCount,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagCount DESC, Tag) as rn
    FROM (
        SELECT
            p.OwnerUserId,
            t.Tag,
            COUNT(*) AS TagCount
        FROM
            Posts p,
            LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(Tag)
        WHERE
            p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
        GROUP BY
            p.OwnerUserId, t.Tag
    ) AS UserTags
),
TopTags AS (
    SELECT
        OwnerUserId,
        string_agg(Tag, ', ' ORDER BY TagCount DESC) AS Top3Tags
    FROM UserTagContributions
    WHERE rn <= 3
    GROUP BY OwnerUserId
),
CommunityEngagement AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven,
        SUM(CASE WHEN v.VoteTypeId = 16 THEN 1 ELSE 0 END) AS EditsApproved,
        COUNT(DISTINCT ph.Id) AS EditsMade
    FROM
        Votes v
    LEFT JOIN PostHistory ph ON v.UserId = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionsAsked,
    uas.AnswersPosted,
    uas.AcceptedAnswers,
    CAST(uas.AcceptedAnswers AS REAL) / NULLIF(uas.AnswersPosted, 0) AS AcceptanceRatio,
    uas.AvgAnswerScore,
    uas.CommentsWritten,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    tt.Top3Tags,
    ce.UpVotesGiven,
    ce.DownVotesGiven,
    ce.EditsMade,
    (
        (uas.Reputation * 0.1) +
        (uas.AnswersPosted * 5) +
        (uas.AcceptedAnswers * 10) +
        (uas.AvgAnswerScore * 2) +
        (uas.QuestionsAsked * 1) +
        (uas.CommentsWritten * 0.5) +
        (uas.GoldBadges * 100) +
        (uas.SilverBadges * 50) +
        (uas.BronzeBadges * 25) +
        (COALESCE(ce.UpVotesGiven, 0) * 0.2) +
        (COALESCE(ce.EditsMade, 0) * 1.5)
    ) AS CalculatedPowerScore
FROM
    UserActivitySummary uas
JOIN
    CommunityEngagement ce ON uas.UserId = ce.UserId
LEFT JOIN
    TopTags tt ON uas.UserId = tt.OwnerUserId
WHERE
    uas.AnswersPosted > 10
    AND uas.LastAccessDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
ORDER BY
    CalculatedPowerScore DESC
LIMIT 250;