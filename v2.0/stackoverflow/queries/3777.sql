-- {"query": "3777.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3168}
WITH UserStats AS (
    SELECT 
        u.Id,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        u.CreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
),
PostAgg AS (
    SELECT 
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(
            CASE 
                WHEN p.Tags IS NOT NULL 
                THEN (CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '><', '')))/2 + 1 
                ELSE 0 
            END
        ) AS TotalTagOccurrences
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
VoteAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod'   THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
TopUserTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        tg.tag AS TagName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY t.Count DESC) AS rn
    FROM Posts p
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags,2,CHAR_LENGTH(p.Tags)-2), '><')) AS tag
    ) tg ON TRUE
    JOIN Tags t ON t.TagName = tg.tag
    WHERE p.OwnerUserId IS NOT NULL
),
MainResults AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        pa.QuestionCount,
        pa.AnswerCount,
        ROUND(CAST(pa.AvgScore AS NUMERIC),2) AS AvgScore,
        pa.LastPostDate,
        pa.TotalTagOccurrences,
        COALESCE(va.UpVotes,0) - COALESCE(va.DownVotes,0) AS NetVotes,
        va.LastVoteDate,
        STRING_AGG(DISTINCT tut.TagName, ', ') FILTER (WHERE tut.rn <= 5) AS TopFiveTags,
        CASE
            WHEN us.Reputation > 20000 AND us.GoldBadges >= 5 THEN 'Elite'
            WHEN us.Reputation > 10000 THEN 'Veteran'
            ELSE 'Member'
        END AS Tier,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.Id AND p.AcceptedAnswerId IS NOT NULL)
            THEN 1 ELSE 0 
        END AS HasAcceptedAnswers,
        CASE 
            WHEN pa.QuestionCount IS NULL OR pa.QuestionCount = 0 
            THEN NULL 
            ELSE ROUND(CAST(pa.AnswerCount AS NUMERIC) / pa.QuestionCount, 2) 
        END AS AnswerToQuestionRatio
    FROM UserStats us
    LEFT JOIN PostAgg pa ON pa.UserId = us.Id
    LEFT JOIN VoteAgg va ON va.PostId = (
        SELECT Id 
        FROM Posts p 
        WHERE p.OwnerUserId = us.Id 
        ORDER BY p.CreationDate DESC 
        LIMIT 1
    )
    LEFT JOIN TopUserTags tut ON tut.UserId = us.Id AND tut.rn <= 5
    WHERE us.Reputation IS NOT NULL
      AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 0
      AND (pa.QuestionCount IS NULL OR pa.QuestionCount > 10)
    GROUP BY 
        us.Id, us.DisplayName, us.Reputation,
        us.GoldBadges, us.SilverBadges, us.BronzeBadges,
        pa.QuestionCount, pa.AnswerCount, pa.AvgScore,
        pa.LastPostDate, pa.TotalTagOccurrences,
        COALESCE(va.UpVotes,0) - COALESCE(va.DownVotes,0), va.LastVoteDate,
        CASE
            WHEN us.Reputation > 20000 AND us.GoldBadges >= 5 THEN 'Elite'
            WHEN us.Reputation > 10000 THEN 'Veteran'
            ELSE 'Member'
        END,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.Id AND p.AcceptedAnswerId IS NOT NULL)
            THEN 1 ELSE 0 
        END,
        CASE 
            WHEN pa.QuestionCount IS NULL OR pa.QuestionCount = 0 
            THEN NULL 
            ELSE ROUND(CAST(pa.AnswerCount AS NUMERIC) / pa.QuestionCount, 2) 
        END
)
SELECT * FROM MainResults
UNION ALL
SELECT 
    NULL AS Id,NULL AS DisplayName,NULL AS Reputation,NULL AS GoldBadges,NULL AS SilverBadges,NULL AS BronzeBadges,
    NULL AS QuestionCount,NULL AS AnswerCount,NULL AS AvgScore,NULL AS LastPostDate,NULL AS TotalTagOccurrences,
    NULL AS NetVotes,NULL AS LastVoteDate,NULL AS TopFiveTags,NULL AS Tier,NULL AS HasAcceptedAnswers,NULL AS AnswerToQuestionRatio
FROM (SELECT 1) AS dummy
EXCEPT
SELECT 
    Id,DisplayName,Reputation,GoldBadges,SilverBadges,BronzeBadges,
    QuestionCount,AnswerCount,AvgScore,LastPostDate,TotalTagOccurrences,
    NetVotes,LastVoteDate,TopFiveTags,Tier,HasAcceptedAnswers,AnswerToQuestionRatio
FROM (
    SELECT * FROM MainResults
) sub
WHERE sub.Tier = 'Member';