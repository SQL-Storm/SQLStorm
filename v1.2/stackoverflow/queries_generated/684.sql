-- {"query": "684.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1516} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        case when p.PostTypeId = 1 then p.AnswerCount else null end as AnswerCount,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
TopPosts as (
    select
        UserId,
        PostId,
        PostTypeId,
        PostCreationDate,
        PostScore,
        ViewCount,
        Tags,
        AcceptedAnswerId,
        AnswerCount
    from RecursiveUserActivity
    where PostRank <= 5
),
AcceptedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 2
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgeSummary as (
    select
        ubc.UserId,
        coalesce(sum(case when ubc.Class = 1 then ubc.BadgeCount else 0 end),0) as GoldBadges,
        coalesce(sum(case when ubc.Class = 2 then ubc.BadgeCount else 0 end),0) as SilverBadges,
        coalesce(sum(case when ubc.Class = 3 then ubc.BadgeCount else 0 end),0) as BronzeBadges
    from UserBadgeCounts ubc
    group by ubc.UserId
),
PostCommentsCount as (
    select
        c.PostId,
        count(*) filter (where c.Score > 0) as PositiveComments,
        count(*) filter (where c.Score <= 0 or c.Score is null) as NonPositiveComments
    from Comments c
    group by c.PostId
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedCount
    from PostLinks pl
    group by pl.PostId
),
PostHistoryCloseVotes as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes
    from PostHistory ph
    group by ph.PostId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreated,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeSummary ubs on ubs.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        a.OwnerUserId as AnswerOwnerUserId,
        abs(extract(epoch from (a.CreationDate - q.CreationDate))) as AnswerTimeSeconds,
        pc.PositiveComments,
        pc.NonPositiveComments,
        pld.DuplicateCount,
        pld.LinkedCount,
        phcv.CloseVotes,
        phcv.ReopenVotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostCommentsCount pc on pc.PostId = q.Id
    left join PostLinkDuplicates pld on pld.PostId = q.Id
    left join PostHistoryCloseVotes phcv on phcv.PostId = q.Id
    where q.PostTypeId = 1
),
AnswerRanks as (
    select
        QuestionId,
        AnswerId,
        AnswerScore,
        row_number() over (partition by QuestionId order by AnswerScore desc, AnswerDate asc) as AnswerRank
    from QuestionsWithAnswers
    where AnswerId is not null
),
TopAnswers as (
    select
        ar.QuestionId,
        ar.AnswerId,
        ar.AnswerScore
    from AnswerRanks ar
    where ar.AnswerRank = 1
),
FinalSummary as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.PositiveComments,
        q.NonPositiveComments,
        q.DuplicateCount,
        q.LinkedCount,
        q.CloseVotes,
        q.ReopenVotes,
        ta.AnswerId as TopAnswerId,
        ta.AnswerScore as TopAnswerScore,
        ua.DisplayName as QuestionOwner,
        ua.Reputation as QuestionOwnerReputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        -- Complex string expression: normalized title length * log(viewcount + 1)
        length(q.Title) * ln(coalesce(q.ViewCount,0) + 1) as TitleViewScore,
        -- NULL logic with COALESCE and CASE
        case
            when q.CloseVotes > 0 then 'Closed'
            when q.ReopenVotes > 0 then 'Reopened'
            else 'Open'
        end as PostStatus
    from QuestionsWithAnswers q
    left join TopAnswers ta on ta.QuestionId = q.QuestionId
    left join Users ua on ua.Id = (select OwnerUserId from Posts where Id = q.QuestionId)
)
select *
from FinalSummary
where TitleViewScore > 20
  and (GoldBadges + SilverBadges + BronzeBadges) > 10
  and PostStatus <> 'Closed'
order by TitleViewScore desc, QuestionScore desc
limit 100;