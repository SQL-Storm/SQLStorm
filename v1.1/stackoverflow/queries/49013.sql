SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.Views AS UserViews,
    MAX(B.Name) FILTER (WHERE B.Class = 1) AS GoldBadge,
    MAX(B.Name) FILTER (WHERE B.Class = 2) AS SilverBadge,
    COUNT(DISTINCT Q_Stats.Id) AS TotalHighScoreEditedDuplicateQuestions,
    AVG(Q_Stats.Score) AS AvgQuestionScore,
    SUM(Q_Stats.EditCount) AS TotalQuestionHistoryEvents,
    AVG(Q_Stats.TimeToFirstBodyEditSeconds) AS AvgTimeToFirstQuestionBodyEditSeconds,
    COUNT(DISTINCT A_Stats.Id) AS TotalHighScoreAcceptedAnswers,
    AVG(A_Stats.Score) AS AvgAnswerScore,
    SUM(A_Stats.CommentCount) AS TotalAnswerComments,
    CommonQuestionTagsSample.CommonTags AS CommonQuestionTagsSample
FROM
    Users AS U
JOIN
    Badges AS B ON U.Id = B.UserId
LEFT JOIN LATERAL (
    SELECT
        P.Id,
        P.OwnerUserId,
        P.Score,
        P.CreationDate,
        P.Tags,
        (SELECT COUNT(*) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,22,24,25,31,33,34,35,36,37,38,50,52,53,66)) AS EditCount,
        (SELECT MIN(EXTRACT(EPOCH FROM (PH_FirstEdit.CreationDate - P.CreationDate)))
         FROM PostHistory PH_FirstEdit
         WHERE PH_FirstEdit.PostId = P.Id AND PH_FirstEdit.PostHistoryTypeId = 5) AS TimeToFirstBodyEditSeconds
    FROM
        Posts AS P
    WHERE
        P.OwnerUserId = U.Id
        AND P.PostTypeId = 1
        AND P.Score > 100
        AND P.ViewCount > 1000
        AND EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3)
        AND (SELECT COUNT(*) FROM PostHistory PH_EditCount WHERE PH_EditCount.PostId = P.Id AND PH_EditCount.PostHistoryTypeId IN (4,5,6)) >= 3
) AS Q_Stats ON Q_Stats.OwnerUserId = U.Id
LEFT JOIN LATERAL (
    SELECT
        P.Id,
        P.OwnerUserId,
        P.Score,
        P.CreationDate,
        (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P.Id) AS CommentCount
    FROM
        Posts AS P
    WHERE
        P.OwnerUserId = U.Id
        AND P.PostTypeId = 2
        AND P.Score > 50
        AND EXISTS (SELECT 1 FROM Posts QUES WHERE QUES.AcceptedAnswerId = P.Id)
) AS A_Stats ON A_Stats.OwnerUserId = U.Id
LEFT JOIN LATERAL (
    -- expand tags from Q_Stats.Tags into rows, then aggregate distinct sample
    SELECT
        STRING_AGG(tag, ', ') AS CommonTags
    FROM (
        SELECT DISTINCT TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM t)) AS tag
        FROM (
            SELECT regexp_split_to_table(COALESCE(Q.Tags,''), '><') AS t
            FROM (
                -- select tags values from the question stats rows for this user
                SELECT Tags
                FROM (SELECT Q2.Tags FROM Posts Q2 WHERE Q2.OwnerUserId = U.Id AND Q2.PostTypeId = 1 AND Q2.Score > 100 AND Q2.ViewCount > 1000 AND EXISTS (SELECT 1 FROM PostLinks PL2 WHERE PL2.PostId = Q2.Id AND PL2.LinkTypeId = 3) AND (SELECT COUNT(*) FROM PostHistory PH2 WHERE PH2.PostId = Q2.Id AND PH2.PostHistoryTypeId IN (4,5,6)) >= 3) AS Q
            ) AS Q
        ) AS split_tags
    ) AS distinct_tags
) AS CommonQuestionTagsSample ON true
WHERE
    B.Class IN (1, 2)
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.Views, CommonQuestionTagsSample.CommonTags
HAVING
    COUNT(DISTINCT Q_Stats.Id) >= 1 OR COUNT(DISTINCT A_Stats.Id) >= 1
ORDER BY
    U.Reputation DESC,
    TotalHighScoreEditedDuplicateQuestions DESC,
    TotalHighScoreAcceptedAnswers DESC,
    U.Views DESC
LIMIT 100;