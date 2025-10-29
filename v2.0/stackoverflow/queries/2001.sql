-- {"query": "2001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1247}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from
        Users u
    left join
        Badges b on b.UserId = u.Id
    where
        b.TagBased = false
),
UserBadgeSummary as (
    select
        UserId,
        count(case when Class = 1 then 1 end) as GoldBadges,
        count(case when Class = 2 then 1 end) as SilverBadges,
        count(case when Class = 3 then 1 end) as BronzeBadges,
        max(Date) as LatestBadgeDate
    from
        RecursiveUserBadges
    group by UserId
),
QuestionAnswers as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate as QuestionDate,
        count(a.Id) as AnswerCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId = p.OwnerUserId then 1 else 0 end) as OwnerAnsweredCount
    from
        Posts p
    left join
        Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where
        p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate
),
PopularAnswers as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.Score,
        u.DisplayName as AnswererName,
        u.Reputation,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from
        Posts a
    left join
        Users u on u.Id = a.OwnerUserId
    where
        a.PostTypeId = 2
),
TopAnswerers as (
    select
        QuestionId,
        AnswererName,
        Reputation,
        Score
    from
        PopularAnswers
    where
        AnswerRank = 1
),
QuestionWithJoinStatus as (
    select 
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.QuestionDate,
        q.AnswerCount,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.OwnerAnsweredCount,
        ta.AnswererName,
        ta.Reputation as AnswererReputation,
        ta.Score as TopAnswerScore,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LatestBadgeDate
    from
        QuestionAnswers q
    left join
        TopAnswerers ta on ta.QuestionId = q.QuestionId
    left join
        UserBadgeSummary ubs on ubs.UserId = q.OwnerUserId
),
CloseReasonCount as (
    select 
        cast(ph.Comment as integer) as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from
        PostHistory ph
    inner join
        CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where
        ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
    group by cast(ph.Comment as integer), crt.Name
),
QuestionCloseMapping as (
    select distinct
        ph.PostId,
        cast(ph.Comment as integer) as CloseReasonId
    from
        PostHistory ph
    where
        ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
),
QuestionsWithClose as (
    select
        q.QuestionId,
        q.Title,
        q.AnswerCount,
        crc.CloseReasonName,
        crc.CloseCount
    from
        QuestionAnswers q
    left join
        QuestionCloseMapping qcm on q.QuestionId = qcm.PostId
    left join
        CloseReasonCount crc on crc.CloseReasonId = qcm.CloseReasonId
),
FinalResult as (
    select 
        qwjs.QuestionId,
        qwjs.Title,
        qwjs.AnswerCount,
        qwjs.AvgAnswerScore,
        qwjs.MaxAnswerScore,
        qwjs.OwnerAnsweredCount,
        qwjs.AnswererName,
        qwjs.AnswererReputation,
        qwjs.TopAnswerScore,
        qwjs.GoldBadges,
        qwjs.SilverBadges,
        qwjs.BronzeBadges,
        qwjs.LatestBadgeDate,
        qc.CloseReasonName,
        qc.CloseCount,
        (
            coalesce(qwjs.Title, 'No Title')
            || ' | Answers: ' || coalesce(cast(qwjs.AnswerCount as varchar), '0')
            || ' | TopAnswerer: ' || coalesce(qwjs.AnswererName, 'N/A')
            || ' | CloseReason: ' || coalesce(qc.CloseReasonName, 'Open')
        ) as SummaryText,
        case
            when qwjs.AnswerCount = 0 then 'Unanswered'
            when qwjs.OwnerAnsweredCount > 0 then 'OP Answered'
            when qwjs.MaxAnswerScore > 10 then 'Hot'
            else 'Normal'
        end as QuestionStatus
    from
        QuestionWithJoinStatus qwjs
    left join
        QuestionsWithClose qc on qc.QuestionId = qwjs.QuestionId
)
select *
from FinalResult
where
    (coalesce(GoldBadges,0) > 0 or coalesce(SilverBadges,0) > 3 or coalesce(BronzeBadges,0) > 5)
    and (CloseReasonName is null or CloseCount < 1000)
    and (AnswerCount between 1 and 10)
order by 
    GoldBadges desc,
    SilverBadges desc,
    BronzeBadges desc,
    AnswerCount desc,
    QuestionId
limit 100;