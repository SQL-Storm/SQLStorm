-- {"query": "4595.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1025} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) as PreviousEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
),
UserEditFrequency AS (
    SELECT
        UserId,
        COUNT(DISTINCT PostId) AS PostsEdited,
        AVG(EXTRACT(EPOCH FROM (CreationDate - PreviousEditDate))) AS AvgEditIntervalSeconds
    FROM RankedPostEdits
    WHERE rn = 1 AND CreationDate > PreviousEditDate
    GROUP BY UserId
    HAVING COUNT(DISTINCT PostId) > 5 AND AVG(EXTRACT(EPOCH FROM (CreationDate - PreviousEditDate))) < 86400 * 7 -- Avg interval less than a week
),
TopEditorsWithPosts AS (
    SELECT
        uef.UserId,
        u.DisplayName AS EditorDisplayName,
        uef.AvgEditIntervalSeconds,
        SUM(p.AnswerCount) AS TotalAnswersOnEditedPosts
    FROM UserEditFrequency uef
    JOIN Users u ON uef.UserId = u.Id
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Questions owned by the editor
    GROUP BY uef.UserId, u.DisplayName, uef.AvgEditIntervalSeconds
    HAVING SUM(p.AnswerCount) IS NULL OR SUM(p.AnswerCount) > 1000
),
PostQuestionDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score AS PostScore,
        pt.Name AS PostTypeName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId AS PostOwnerUserId,
        u_owner.DisplayName AS PostOwnerDisplayName,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
    WHERE p.PostTypeId = 1 -- Questions only
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT
    tewp.EditorDisplayName,
    tewp.AvgEditIntervalSeconds,
    tewp.TotalAnswersOnEditedPosts,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    pqd.Title AS SampleQuestionTitle,
    pqd.PostScore AS SampleQuestionScore,
    pqd.PostStatus,
    pqd.PostOwnerDisplayName,
    CONCAT(
        pqd.PostTypeName,
        ' - ',
        CASE
            WHEN pqd.PostOwnerUserId = tewp.UserId THEN 'Owner'
            WHEN pqd.PostOwnerUserId IS NULL THEN 'Community'
            ELSE 'Other'
        END,
        ' - ',
        IIF(pqd.PostScore > 100, 'High Score', IIF(pqd.PostScore < 0, 'Negative Score', 'Average Score'))
    ) AS PostCharacteristic
FROM TopEditorsWithPosts tewp
LEFT JOIN UserBadgeCounts ubc ON tewp.UserId = ubc.UserId
LEFT JOIN Posts p_sample ON tewp.UserId = p_sample.OwnerUserId AND p_sample.PostTypeId = 1 -- Sample a post owned by the editor
LEFT JOIN PostQuestionDetails pqd ON p_sample.Id = pqd.PostId
WHERE pqd.PostScore > 50 -- Only consider questions with a decent score
ORDER BY tewp.AvgEditIntervalSeconds ASC, ubc.GoldBadges DESC, tewp.TotalAnswersOnEditedPosts DESC
LIMIT 10;
