with UserParticipation as (
    select 
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        coalesce(sum(v.TotalVotes), 0) as TotalVotesReceived,
        first_value(u.Reputation) over (partition by u.Id order by 1) as ReputationAlways,
        dense_rank() over (partition by community_ids.maxBadgeClass order by coalesce(u.Reputation, 0) desc) as rankByRepPerClass
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select p.PostTypeId, p.OwnerUserId, count(*) as TotalVotes
        from Posts p
        join Votes v2 on v2.PostId = p.Id
        where v2.VoteTypeId in (2, 3)
        group by p.PostTypeId, p.OwnerUserId
    ) v on v.OwnerUserId = u.Id
    cross join lateral (
        select max(case when Class = 1 then 1 else 0 end) as maxBadgeClass
        from (
            -- placeholder for community_ids source; original query referenced community_ids but did not define it.
            -- If community_ids is a table, replace the below select with: select Class from community_ids where community_ids.UserId = u.Id
            select 0 as Class
        ) cid
    ) community_ids
    group by u.Id, u.Reputation, community_ids.maxBadgeClass
)
select *
from UserParticipation;