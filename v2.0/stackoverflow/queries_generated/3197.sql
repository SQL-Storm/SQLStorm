-- {"query": "3197.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2017} 

WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v  ON v.UserId = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

AnswerInfo AS (
    SELECT
        a.OwnerUserId               AS UserId,
        a.Id                        AS AnswerId,
        a.ParentId                  AS QuestionId,
        a.Score                     AS AnswerScore,
        a.CreationDate,
        q.Title,
        q.Tags,
        ph.CloseReasonId,
        ph.CloseReasonJson
    FROM Posts a
    JOIN Posts q
        ON q.Id = a.ParentId
       AND q.PostTypeId = 1                      -- only questions
    LEFT JOIN LATERAL (
        SELECT
            CAST(ph.Comment AS int) AS CloseReasonId,
            ph.Text                  AS CloseReasonJson
        FROM PostHistory ph
        WHERE ph.PostId = q.Id
          AND ph.PostHistoryTypeId = 10          -- post closed
        ORDER BY ph.CreationDate DESC
        LIMIT 1
    ) ph ON TRUE
    WHERE a.PostTypeId = 2                       -- only answers
      AND EXISTS (
            SELECT 1
            FROM PostHistory ph2
            WHERE ph2.PostId = q.Id
              AND ph2.PostHistoryTypeId = 10
              AND CAST(ph2.Comment AS int) = 101   -- duplicate close reason
      )
),

TagExplode AS (
    SELECT
        ai.*,
        UNNEST(regexp_split_to_array(
                SUBSTRING(ai.Tags FROM 2 FOR LENGTH(ai.Tags)-2),
                '><')) AS Tag
    FROM AnswerInfo ai
),

RankedUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.UpVotes,
        us.DownVotes,
        COUNT(DISTINCT te.Tag)                     AS DistinctTagsAnswered,
        AVG(ai.AnswerScore)                        AS AvgAnswerScore,
        MAX(ai.CreationDate)                       AS LastAnswerDate,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC,
                                   AVG(ai.AnswerScore) DESC) AS Rank
    FROM UserStats us
    JOIN AnswerInfo ai   ON ai.UserId = us.Id
    JOIN TagExplode te   ON te.AnswerId = ai.AnswerId
    GROUP BY us.Id, us.DisplayName, us.Reputation,
             us.GoldBadges, us.SilverBadges, us.BronzeBadges,
             us.UpVotes, us.DownVotes
),

FinalSet AS (
    SELECT *
    FROM RankedUsers
    WHERE Rank <= 10
)

SELECT
    f.Id,
    f.DisplayName,
    f.Reputation,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.UpVotes,
    f.DownVotes,
    f.DistinctTagsAnswered,
    ROUND(f.AvgAnswerScore::numeric, 2)          AS AvgAnswerScore,
    f.LastAnswerDate,
    f.Rank,
    COALESCE(
        (
            SELECT STRING_AGG(t.TagName, ', ')
            FROM Tags t
            WHERE t.TagName = ANY (
                SELECT DISTINCT te.Tag
                FROM AnswerInfo ai
                JOIN TagExplode te ON te.AnswerId = ai.AnswerId
                WHERE ai.UserId = f.Id
            )
            LIMIT 5
        ),
        'None'
    )                                            AS SampleTags
FROM FinalSet f
ORDER BY f.Rank;
