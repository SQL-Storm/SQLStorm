-- {"query": "721.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1823} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(vb.BountyAmount), 0) as TotalBountyGiven,
        row_number() over (partition by u.Id order by ph.CreationDate desc nulls last) as LastEditRank,
        ph.CreationDate as LastEditDate,
        ph.PostHistoryTypeId,
        ph.Comment as CloseReasonCode
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 -- BountyStart
        left join PostHistory ph on ph.UserId = u.Id
    group by
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ph.CreationDate, ph.PostHistoryTypeId, ph.Comment
),
FilteredUserActivity as (
    select
        UserId,
        DisplayName,
        Reputation,
        CreationDate,
        LastAccessDate,
        QuestionsCount,
        AnswersCount,
        TotalBountyGiven,
        max(LastEditDate) filter (where LastEditRank = 1) as MostRecentEditDate,
        max(case 
            when PostHistoryTypeId = 10 then CloseReasonCode 
            else null end) as LastCloseReasonCode
    from RecursiveUserActivity
    group by
        UserId, DisplayName, Reputation, CreationDate, LastAccessDate, QuestionsCount, AnswersCount, TotalBountyGiven
),
TagQuestionStats as (
    select
        t.Id as TagId,
        t.TagName,
        count(distinct p.Id) as QuestionCount,
        avg(p.Score) as AvgQuestionScore,
        sum(p.ViewCount) as TotalViews,
        max(p.CreationDate) as LatestQuestionDate
    from
        Tags t
        left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    group by
        t.Id, t.TagName
),
TopUsersByTag as (
    select
        t.TagId,
        t.TagName,
        fua.UserId,
        fua.DisplayName,
        count(p.Id) as AnswersToTagQuestions,
        row_number() over (partition by t.TagId order by count(p.Id) desc) as rn
    from
        TagQuestionStats t
        join Posts p on p.PostTypeId = 2 and p.ParentId in (
            select Id from Posts where PostTypeId = 1 and Tags like concat('%<', t.TagName, '>%')
        )
        join FilteredUserActivity fua on fua.UserId = p.OwnerUserId
    group by
        t.TagId, t.TagName, fua.UserId, fua.DisplayName
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from
        Badges b
    group by
        b.UserId
),
UserActivityWindow as (
    select
        fua.*,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.DistinctBadges,
        dense_rank() over (order by fua.Reputation desc) as ReputationRank,
        coalesce(fua.AnswersCount::float / nullif(fua.QuestionsCount,0), 0) as AnswerQuestionRatio
    from
        FilteredUserActivity fua
        left join UserBadgeSummary ubs on ubs.UserId = fua.UserId
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) as DuplicateCount
    from
        PostLinks pl
        join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    group by
        pl.PostId
),
QuestionAnswerWithVotes as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.ViewCount,
        q.Score as QuestionScore,
        q.Tags,
        a.Id as AnswerId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as AnswerUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as AnswerDownVotes,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from
        Posts q
        left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        left join Votes v on v.PostId = a.Id
    where
        q.PostTypeId = 1
    group by
        q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.Tags,
        a.Id, a.CreationDate, a.Score, a.OwnerUserId
),
TopAnswersWithComments as (
    select
        qa.QuestionId,
        qa.Title,
        qa.AnswerId,
        qa.AnswerScore,
        qa.AnswerUpVotes,
        qa.AnswerDownVotes,
        qa.AnswerOwner,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters,
        lead(qa.AnswerScore) over (partition by qa.QuestionId order by qa.AnswerScore desc) as NextAnswerScore
    from
        QuestionAnswerWithVotes qa
        left join Comments c on c.PostId = qa.AnswerId
    where
        qa.AnswerRank <= 3
    group by
        qa.QuestionId, qa.Title, qa.AnswerId, qa.AnswerScore, qa.AnswerUpVotes, qa.AnswerDownVotes, qa.AnswerOwner
)
select
    uaw.UserId,
    uaw.DisplayName,
    uaw.Reputation,
    uaw.QuestionsCount,
    uaw.AnswersCount,
    uaw.TotalBountyGiven,
    uaw.GoldBadges,
    uaw.SilverBadges,
    uaw.BronzeBadges,
    uaw.DistinctBadges,
    uaw.ReputationRank,
    uaw.AnswerQuestionRatio,
    tqs.TagName,
    tqs.QuestionCount,
    tqs.AvgQuestionScore,
    tqs.TotalViews,
    tqs.LatestQuestionDate,
    tut.AnswersToTagQuestions,
    dl.DuplicateCount,
    ta.Title,
    ta.AnswerScore,
    ta.AnswerUpVotes,
    ta.AnswerDownVotes,
    ta.CommentCount,
    ta.Commenters,
    ta.NextAnswerScore,
    case
        when uaw.LastCloseReasonCode is not null then
            case uaw.LastCloseReasonCode
                when '101' then 'Duplicate'
                when '102' then 'Off-topic'
                when '103' then 'Needs details or clarity'
                when '104' then 'Needs more focus'
                when '105' then 'Opinion-based'
                else 'Other'
            end
        else 'None'
    end as LastCloseReason
from
    UserActivityWindow uaw
    left join TopUsersByTag tut on tut.UserId = uaw.UserId
    left join TagQuestionStats tqs on tqs.TagId = tut.TagId
    left join DuplicateLinkCounts dl on dl.PostId = (
        select p.Id from Posts p where p.OwnerUserId = uaw.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1
    )
    left join TopAnswersWithComments ta on ta.AnswerOwner = uaw.UserId and ta.AnswerScore > 0
where
    uaw.Reputation > 1000
    and tqs.QuestionCount > 50
order by
    uaw.ReputationRank asc,
    tqs.QuestionCount desc,
    tut.AnswersToTagQuestions desc
limit 100;