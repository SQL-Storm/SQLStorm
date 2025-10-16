-- {"query": "1110.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1626} 

with Recursive QuestionPaths as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        1 as Depth,
        array[p.Id] as Path,
        u.DisplayName as OwnerName,
        p.Tags
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1

    union all

    select 
        q.QuestionId,
        a.Title,
        a.CreationDate,
        a.Score,
        qp.Depth + 1,
        qp.Path || a.Id,
        u.DisplayName,
        a.Tags
    from QuestionPaths qp
    join Posts a on a.ParentId = qp.Path[array_length(qp.Path,1)]
        and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where not a.Id = any(qp.Path)
),
BadgeCounts as (
    select 
        UserId, 
        count(*) as TotalBadges,
        count(case when Class = 1 then 1 end) as GoldBadges,
        count(case when Class = 2 then 1 end) as SilverBadges,
        count(case when Class = 3 then 1 end) as BronzeBadges
    from Badges
    group by UserId
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(bc.TotalBadges,0) as TotalBadges,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as UserRank,
        exists (
            select 1 from Posts p 
            where p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.ClosedDate is null
        ) as HasOpenQuestions,
        (
            select count(*) from Comments c where c.UserId = u.Id and c.CreationDate > now() - interval '30 days'
        ) as RecentCommentsCount
    from Users u
    left join BadgeCounts bc on bc.UserId = u.Id
),
PostVotesAgg as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoriteCount, /* may be 0 after Oct 2022 */
        sum(coalesce(v.BountyAmount,0)) filter (where v.VoteTypeId in (8,9)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
TagQuestions as (
    select
        t.TagName,
        count(distinct p.Id) as QuestionCount,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews,
        array_agg(distinct p.OwnerUserId) filter (where p.OwnerUserId is not null) as UsersInvolved
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like ('%<' || t.TagName || '>%')
    group by t.TagName
)
select distinct
    qp.QuestionId,
    substr(qp.Title,1,100) as ShortTitle,
    qp.CreationDate as QuestionCreation,
    qp.Score as QuestionScore,
    qp.Depth,
    qp.Path,
    qp.OwnerName,
    ua.DisplayName as QuestionOwnerDisplayName,
    ua.Reputation as QuestionOwnerReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.RecentCommentsCount,
    (select count(distinct PostLinks.RelatedPostId) 
        from PostLinks 
        where PostLinks.PostId = qp.Path[array_length(qp.Path,1)] and PostLinks.LinkTypeId = 1
    ) as NumLinkedPosts,
    coalesce(pv.UpVotes,0) as PostUpVotes,
    coalesce(pv.DownVotes,0) as PostDownVotes,
    coalesce(pv.FavoriteCount,0) as PostFavorites,
    coalesce(pv.TotalBounty,0) as PostBountyAmount,
    tQ.QuestionCount as TagQuestionCount,
    tQ.AvgScore as TagAvgScore,
    tQ.TotalViews as TagTotalViews,
    -- Compute text similarity and lower-case tags with string ops:
    length(qp.Tags) - length(replace(lower(qp.Tags), 'sql', '')) as SqlTagCount,
    case 
        when qp.Tags is null then 'No Tags' 
        else regexp_replace(qp.Tags, '[<>]', ',', 'g') 
    end as CleanTags,
    row_number() over (partition by qp.OwnerName order by qp.Score desc) as OwnerPostRank,
    case 
        when qp.Depth > 1 and pv.UpVotes < pv.DownVotes then 'Controversial Answer'
        when qp.Depth = 1 and qp.Score > 100 then 'Popular Question'
        else 'Other'
    end as PostClassification,
    -- Correlated subquery: Find latest comment on question
    (select c.Text from Comments c where c.PostId = qp.QuestionId order by c.CreationDate desc limit 1) as LatestQuestionComment,
    -- Outer apply to find if question is closed and reason
    ph.Comment as CloseReason,
    ph.CreationDate as CloseDate
from QuestionPaths qp
left join UserActivity ua on ua.DisplayName = qp.OwnerName
left join PostVotesAgg pv on pv.PostId = qp.Path[array_length(qp.Path,1)]
left join LATERAL (
    select ph2.Comment, ph2.CreationDate
    from PostHistory ph2 
    where ph2.PostId = qp.QuestionId and ph2.PostHistoryTypeId = 10
    order by ph2.CreationDate desc limit 1
) ph on true
left join TagQuestions tQ on tQ.TagName = 
    (select unnest(string_to_array(substr(qp.Tags,2,length(qp.Tags)-2), '><')) limit 1)
where qp.Score > 10 or qp.Depth > 1
order by qp.Score desc, qp.Depth asc
limit 50
union all
select 
    null as QuestionId,
    null as ShortTitle,
    null as QuestionCreation,
    null as QuestionScore,
    null as Depth,
    null as Path,
    null as OwnerName,
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.RecentCommentsCount,
    null as NumLinkedPosts,
    null as PostUpVotes,
    null as PostDownVotes,
    null as PostFavorites,
    null as PostBountyAmount,
    null as TagQuestionCount,
    null as TagAvgScore,
    null as TagTotalViews,
    null as SqlTagCount,
    null as CleanTags,
    null as OwnerPostRank,
    null as PostClassification,
    null as LatestQuestionComment,
    null as CloseReason,
    null as CloseDate
from UserActivity u
where u.UserRank <= 10;
