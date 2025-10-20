with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%' and p.PostTypeId = 1
    left join Users u on p.OwnerUserId = u.Id
    where t.Count > 1000
),
TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then b.Id end) as GoldBadges,
        count(case when b.Class = 2 then b.Id end) as SilverBadges,
        count(case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostVoteStats as (
    select
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        count(case when v.VoteTypeId = 2 then v.Id end) as UpVotes,
        count(case when v.VoteTypeId = 3 then v.Id end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id, p.Score, p.ViewCount
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        a.Id as AnswerId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
FilteredQuestionAnswers as (
    select
        QuestionId,
        Title,
        QuestionDate,
        AnswerId,
        AnswerDate,
        AnswerScore
    from QuestionAnswerStats
    where AnswerRank <= 3
),
CloseReasonsCount as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        sum(coalesce(vs.UpVotes,0)) as TotalUpVotes,
        sum(coalesce(vs.DownVotes,0)) as TotalDownVotes,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostVoteStats vs on vs.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
)
select
    t.TagName,
    t.Count as TagUsage,
    t.PostId,
    t.Score as PostScore,
    t.ViewCount,
    t.CreationDate as PostCreation,
    coalesce(u.DisplayName, 'Unknown') as OwnerName,
    coalesce(ub.GoldBadges,0) as OwnerGoldBadges,
    coalesce(ub.SilverBadges,0) as OwnerSilverBadges,
    coalesce(ub.BronzeBadges,0) as OwnerBronzeBadges,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.TotalBounty,
    qa.Title as QuestionTitle,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerDate,
    cr.CloseReasonName,
    cr.CloseCount,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.TotalPostScore,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.UserRank,
    case
        when ua.Reputation > 100000 then 'Legendary'
        when ua.Reputation > 10000 then 'Expert'
        when ua.Reputation > 1000 then 'Intermediate'
        else 'Beginner'
    end as ReputationLevel,
    (coalesce(t.TagName, '') || ' | ' ||
     coalesce(u.DisplayName, '') || ' | ' ||
     coalesce(qa.Title, '') || ' | ' ||
     coalesce(cr.CloseReasonName, '') || ' | ' ||
     coalesce(cast(ua.UserRank as varchar), '')
    ) as CompositeString
from TopTagPosts t
left join Users u on t.OwnerUserId = u.Id
left join UserBadgeStats ub on u.Id = ub.UserId
left join PostVoteStats pvs on t.PostId = pvs.PostId
left join FilteredQuestionAnswers qa on qa.QuestionId = t.PostId
left join CloseReasonsCount cr on cr.CloseReasonId = (
    select ph.Comment from PostHistory ph
    where ph.PostId = t.PostId and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc
    limit 1
)
left join UserActivityWindow ua on ua.Id = t.OwnerUserId
where t.Score > 5 and (coalesce(pvs.UpVotes,0) - coalesce(pvs.DownVotes,0)) > 3
group by
    t.TagName,
    t.Count,
    t.PostId,
    t.Score,
    t.ViewCount,
    t.CreationDate,
    u.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.TotalBounty,
    qa.Title,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerDate,
    cr.CloseReasonName,
    cr.CloseCount,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.TotalPostScore,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.UserRank,
    ua.Reputation
order by t.Count desc, t.Score desc, ua.UserRank asc
limit 100;