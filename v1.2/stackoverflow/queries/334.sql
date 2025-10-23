-- {"query": "334.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1403} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    inner join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
AcceptedAnswerDetails as (
    select
        a.Id,
        a.ParentId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts a
    inner join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserBadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgePivot as (
    select
        UserId,
        coalesce(max(case when Class = 1 then BadgeCount end), 0) as GoldBadges,
        coalesce(max(case when Class = 2 then BadgeCount end), 0) as SilverBadges,
        coalesce(max(case when Class = 3 then BadgeCount end), 0) as BronzeBadges
    from UserBadgeSummary
    group by UserId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivityWithBadges as (
    select
        rua.*,
        ubp.GoldBadges,
        ubp.SilverBadges,
        ubp.BronzeBadges
    from RecursiveUserActivity rua
    left join UserBadgePivot ubp on ubp.UserId = rua.UserId
),
QuestionAnswerStats as (
    select
        tq.Id as QuestionId,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Score as QuestionScore,
        tq.ViewCount,
        tq.CreationDate as QuestionCreationDate,
        tq.Tags,
        tq.AcceptedAnswerId,
        aad.AnswerScore,
        aad.AnswerCreationDate,
        aad.AnswerOwnerName,
        aad.AnswerOwnerReputation,
        qcr.CloseReason,
        qcr.CloseDate,
        (select count(*) from Comments c where c.PostId = tq.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = tq.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = tq.Id and v.VoteTypeId = 3) as DownVotes
    from TopQuestions tq
    left join AcceptedAnswerDetails aad on aad.Id = tq.AcceptedAnswerId
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
),
RankedQuestions as (
    select
        qas.*,
        rank() over (partition by qas.OwnerUserId order by qas.QuestionScore desc, qas.ViewCount desc) as OwnerQuestionRank,
        dense_rank() over (order by qas.QuestionScore desc, qas.ViewCount desc) as GlobalQuestionRank
    from QuestionAnswerStats qas
),
FinalSelection as (
    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.QuestionCount,
        r.AnswerCount,
        r.CommentCount,
        r.BadgeCount,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        rq.QuestionId,
        rq.Title,
        rq.QuestionScore,
        rq.ViewCount,
        rq.Tags,
        rq.AcceptedAnswerId,
        rq.AnswerScore,
        rq.AnswerCreationDate,
        rq.AnswerOwnerName,
        rq.AnswerOwnerReputation,
        rq.CloseReason,
        rq.CloseDate,
        rq.CommentCount as QuestionCommentCount,
        rq.UpVotes,
        rq.DownVotes,
        rq.OwnerQuestionRank,
        rq.GlobalQuestionRank,
        -- Complex string expression: concatenate tags with user display name and question title
        concat_ws(' | ',
            r.DisplayName,
            rq.Title,
            coalesce(replace(replace(rq.Tags, '><', ', '), '<', ''), 'No Tags')
        ) as UserQuestionTagSummary,
        -- Complex calculation: weighted score with null logic and conditional
        case
            when rq.AnswerScore is not null then rq.QuestionScore * 0.6 + rq.AnswerScore * 0.4
            else rq.QuestionScore * 1.0
        end as WeightedScore,
        -- Window function: cumulative sum of question scores per user ordered by question creation date
        sum(rq.QuestionScore) over (partition by r.UserId order by rq.QuestionId rows between unbounded preceding and current row) as CumulativeQuestionScore
    from UserActivityWithBadges r
    left join RankedQuestions rq on rq.OwnerUserId = r.UserId and rq.OwnerQuestionRank <= 3
)
select *
from FinalSelection
where WeightedScore > 10
  and (GoldBadges > 0 or SilverBadges > 2)
  and (CloseReason is null or CloseReason not like '%Duplicate%')
order by Reputation desc, WeightedScore desc, GlobalQuestionRank
limit 100;