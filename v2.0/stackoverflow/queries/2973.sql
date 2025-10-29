-- {"query": "2973.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1195}
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        rank() over (order by u.Reputation desc nulls last, u.CreationDate asc) as RepRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostScoresAgg as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(p.Id) as PostCount,
        sum(coalesce(p.Score,0)) as TotalScore,
        avg(coalesce(p.Score,0)) as AvgScore,
        max(p.Score) as MaxScore,
        sum(case when p.PostTypeId = 1 then coalesce(p.ViewCount,0) else 0 end) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId, p.PostTypeId
),
RecentActivityCTE as (
    select distinct
        p.OwnerUserId,
        max(coalesce(p.LastActivityDate, p.CreationDate)) over (partition by p.OwnerUserId) as LastActivity,
        min(p.CreationDate) over (partition by p.OwnerUserId) as FirstPostDate
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
),
TopTagsPerUser as (
    -- Split tags stored like '<tag1><tag2>' into rows without using UNNEST/STRING_TO_ARRAY
    -- This implementation uses a recursive CTE to extract tags in a SQL-dialect-compatible way
    with recursive tag_split as (
        select
            u.Id as UserId,
            p.Id as PostId,
            trim(both '<>' from substring(p.Tags from 1 for case when position('>' in p.Tags)=0 then char_length(p.Tags) else position('>' in p.Tags) end)) as Tag,
            -- remaining part after the first '>' character
            case
                when position('>' in p.Tags) = 0 then null
                else substring(p.Tags from position('>' in p.Tags)+1)
            end as rest
        from Users u
        join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
        union all
        select
            ts.UserId,
            ts.PostId,
            trim(both '<>' from substring(ts.rest from 1 for case when position('>' in ts.rest)=0 then char_length(ts.rest) else position('>' in ts.rest) end)) as Tag,
            case
                when ts.rest is null then null
                when position('>' in ts.rest) = 0 then null
                else substring(ts.rest from position('>' in ts.rest)+1)
            end as rest
        from tag_split ts
        where ts.rest is not null and ts.rest <> ''
    )
    select
        UserId,
        Tag,
        count(*) as TagCount,
        row_number() over (partition by UserId order by count(*) desc) as TagRank
    from tag_split
    group by UserId, Tag
),
TagScores as (
    select
        t.TagName,
        coalesce(sum(p.Score),0) as TotalTagScore,
        count(p.Id) as TotalTagPosts
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like '%' || '<' || t.TagName || '>' || '%'
    group by t.TagName
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        u.DisplayName as CloserDisplayName,
        ph.UserId as CloserUserId
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
DuplicateLinkPairs as (
    select 
        pl.PostId,
        q1.Title as QuestionTitle,
        pl.RelatedPostId,
        q2.Title as DuplicateOfTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts q1 on q1.Id = pl.PostId and q1.PostTypeId = 1
    join Posts q2 on q2.Id = pl.RelatedPostId and q2.PostTypeId = 1
    where pl.LinkTypeId = 3
)
select
    ubc.DisplayName,
    ubc.RepRank,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    coalesce(psa.TotalScore,0) as TotalPostScore,
    coalesce(psa.PostCount,0) as TotalPosts,
    rct.LastActivity,
    rct.FirstPostDate,
    coalesce(tt.Tag, 'N/A') as TopTag,
    coalesce(tt.TagCount, 0) as TopTagCount,
    coalesce(ts.TotalTagScore, 0) as TopTagTotalScore,
    case 
        when coalesce(psa.TotalScore, 0) = 0 then 'No Score'
        when psa.TotalScore > 0 then 'Positive Score'
        else 'Negative Score'
    end as ScoreSentiment,
    (
        select p.Id
        from Posts p
        where p.OwnerUserId = ubc.UserId 
          and p.PostTypeId in (1,2)
        order by abs(
            (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2)
            - (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3)
        ) desc
        limit 1
    ) as MostControversialPostId
from UserBadgeCounts ubc
left join PostScoresAgg psa on psa.OwnerUserId = ubc.UserId
left join RecentActivityCTE rct on rct.OwnerUserId = ubc.UserId
left join (
    select UserId, Tag, TagCount from TopTagsPerUser where TagRank = 1
) tt on tt.UserId = ubc.UserId
left join TagScores ts on ts.TagName = tt.Tag
where ubc.RepRank <= 100
order by ubc.RepRank;