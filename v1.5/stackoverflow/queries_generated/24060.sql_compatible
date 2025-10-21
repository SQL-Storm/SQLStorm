WITH
tag_parsed AS (
    SELECT
        p.Id          AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.ClosedDate,
        UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
tag_stats AS (
    SELECT
        TagName,
        COUNT(*)       AS QCount,
        AVG(Score)     AS AvgScore,
        MAX(ViewCount) AS MaxViews
    FROM tag_parsed
    GROUP BY TagName
),
tag_rank AS (
    SELECT
        TagName,
        QCount,
        AvgScore,
        MaxViews,
        ROW_NUMBER() OVER (ORDER BY QCount DESC, MaxViews DESC) AS Rank
    FROM tag_stats
),
gold_users AS (
    SELECT
        u.Id          AS UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCnt
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
gold_answered AS (
    SELECT
        a.Id         AS AnswerId,
        a.ParentId   AS QuestionId,
        u.Id         AS UserId
    FROM Posts a
    JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
      AND u.Id IN (SELECT UserId FROM gold_users)
),
gold_answer_counts AS (
    SELECT
        QuestionId,
        COUNT(*) AS GoldAnswerCnt
    FROM gold_answered
    GROUP BY QuestionId
),
earliest_vote AS (
    SELECT
        v.PostId,
        MIN(v.CreationDate) AS FirstVoteDate
    FROM Votes v
    GROUP BY v.PostId
),
tag_enriched AS (
    SELECT
        tr.TagName,
        tr.QCount,
        tr.AvgScore,
        tr.MaxViews,
        tr.Rank,
        CASE WHEN tr.QCount > 0 THEN 1 ELSE 0 END        AS HasQuestions,
        CASE WHEN tr.MaxViews > 1000 THEN 'High' ELSE 'Low' END AS ViewAbundance,
        STRING_AGG(tp_outer.Title, '; ' ORDER BY tp_outer.Score DESC) AS TopTitles,
        COALESCE(
            (SELECT gac.GoldAnswerCnt
             FROM gold_answer_counts gac
             JOIN tag_parsed tp_join ON tp_join.PostId = gac.QuestionId
             WHERE tp_join.TagName = tr.TagName
             LIMIT 1),
            0) AS SampleGoldAnsCnt,
        COALESCE(
            (SELECT ev.FirstVoteDate
             FROM earliest_vote ev
             JOIN tag_parsed tp_join ON tp_join.PostId = ev.PostId
             WHERE tp_join.TagName = tr.TagName
             LIMIT 1),
            TIMESTAMP '1900-01-01') AS SampleFirstVote
    FROM tag_rank tr
    JOIN tag_parsed tp_outer ON tp_outer.TagName = tr.TagName
    GROUP BY tr.TagName, tr.QCount, tr.AvgScore, tr.MaxViews, tr.Rank
)
SELECT *
FROM
(
    SELECT *
    FROM tag_enriched
    WHERE Rank <= 5
    UNION ALL
    SELECT *
    FROM tag_enriched
    WHERE Rank > 5
      AND AvgScore > 4
) AS final_result
ORDER BY final_result.Rank,
         final_result.ViewAbundance DESC,
         final_result.AvgScore DESC;