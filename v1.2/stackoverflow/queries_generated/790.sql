-- {"query": "790.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1607} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.OwnerUserId, -1) as OwnerUserId,
        p.Id as PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        case when p.Tags is null then array[]::varchar[] else string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><') end as TagArray
    from Tags t
    left join Posts p on p.PostTypeId = 1 and position(t.TagName in coalesce(p.Tags, '')) > 0
), UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
), PostVoteStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 1) as AcceptedByOriginatorVotes,
        max(v.CreationDate) as LastVoteDate
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
), LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc
), UserActivityRank as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
        count(distinct c.Id) as TotalComments,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), QuestionAnswerAggregates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        coalesce(ans.AnswerCount, 0) as AnswerCount,
        coalesce(acc.AnswerId, -1) as AcceptedAnswerId,
        acc.Score as AcceptedAnswerScore,
        acc.OwnerUserId as AcceptedAnswerOwnerUserId,
        ua.DisplayName as AcceptedAnswerOwnerName,
        ua.Reputation as AcceptedAnswerOwnerReputation
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on ans.ParentId = q.Id
    left join Posts acc on acc.Id = q.AcceptedAnswerId
    left join Users ua on ua.Id = acc.OwnerUserId
    where q.PostTypeId = 1
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreatorName
    from PostLinks pl
    left join Users u on u.Id = (select ph.UserId from PostHistory ph where ph.PostId = pl.PostId order by ph.CreationDate limit 1)
    where pl.LinkTypeId = 3
), UserBadgeRankings as (
    select
        ubc.UserId,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        (ubc.GoldBadges * 3 + ubc.SilverBadges * 2 + ubc.BronzeBadges) as BadgeScore,
        rank() over (order by (ubc.GoldBadges * 3 + ubc.SilverBadges * 2 + ubc.BronzeBadges) desc) as BadgeRank
    from UserBadgeCounts ubc
    join Users u on u.Id = ubc.UserId
)
select
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    uar.TotalQuestions,
    uar.TotalAnswers,
    uar.TotalComments,
    uar.ReputationRank,
    coalesce(ubc.GoldBadges, 0) as GoldBadges,
    coalesce(ubc.SilverBadges, 0) as SilverBadges,
    coalesce(ubc.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubr.BadgeRank, null) as BadgeRank,
    qa.QuestionId,
    qa.Title,
    qa.QuestionScore,
    qa.QuestionViews,
    qa.AnswerCount,
    qa.AcceptedAnswerId,
    qa.AcceptedAnswerScore,
    qa.AcceptedAnswerOwnerUserId,
    qa.AcceptedAnswerOwnerName,
    qa.AcceptedAnswerOwnerReputation,
    dv.DuplicateCount,
    dup.LinkCount,
    dup.LinkCreatorName,
    case
        when qa.QuestionScore >= 50 then 'Hot'
        when qa.QuestionScore between 20 and 49 then 'Trending'
        else 'Normal'
    end as QuestionPopularity,
    row_number() over (partition by uar.UserId order by qa.QuestionScore desc) as UserQuestionRank,
    max(pvs.LastVoteDate) over (partition by uar.UserId) as LastVoteDateForUserPosts,
    case when uar.LastAccessDate > now() - interval '30 days' then true else false end as ActiveRecently
from UserActivityRank uar
left join UserBadgeCounts ubc on ubc.UserId = uar.UserId
left join UserBadgeRankings ubr on ubr.UserId = uar.UserId
left join QuestionAnswerAggregates qa on qa.AcceptedAnswerOwnerUserId = uar.UserId
left join (
    select OwnerUserId, count(*) as DuplicateCount
    from Posts p
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    group by OwnerUserId
) dv on dv.OwnerUserId = uar.UserId
left join (
    select
        pl.PostId,
        count(pl.Id) as LinkCount,
        max(u.DisplayName) as LinkCreatorName
    from PostLinks pl
    left join Users u on u.Id = (select ph.UserId from PostHistory ph where ph.PostId = pl.PostId order by ph.CreationDate limit 1)
    group by pl.PostId
) dup on dup.PostId = qa.QuestionId
left join PostVoteStats pvs on pvs.OwnerUserId = uar.UserId
where uar.Reputation > 1000
order by uar.ReputationRank, UserQuestionRank
limit 100;