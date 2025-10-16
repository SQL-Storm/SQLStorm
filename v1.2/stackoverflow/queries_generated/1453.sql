-- {"query": "1453.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1457} 
with recursive tag_paths as (
    select
        p.Id post_id,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag,
        p.OwnerUserId,
        1 as path_length
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null

    union all

    select
        tp.post_id,
        t.TagName,
        tp.OwnerUserId,
        tp.path_length + 1
    from tag_paths tp
    join Tags t on t.TagName <> tp.tag and t.Id < 100 -- arbitrary restriction to limit recursion depth join join condition care; this join attempts to simulate tag transitions but by ID filters to limit joined size
    where tp.path_length < 2
),
filtered_posts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        coalesce(p.Tags, '') as Tags,
        COALESCE(u.DisplayName, 'Unknown') as OwnerUserName,
        (select count(*) from Comments c where c.PostId = p.Id and c.Score > 0) as PositiveCommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotesCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotesCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as rn_desc_score
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
post_history_windows as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        phr.Name as HistoryTypeName,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        lag(ph.PostHistoryTypeId) over (partition by ph.PostId order by ph.CreationDate) as prev_historytype,
        lead(ph.PostHistoryTypeId) over (partition by ph.PostId order by ph.CreationDate) as next_historytype,
        count(ph.PostHistoryTypeId) over (partition by ph.PostId, ph.PostHistoryTypeId) as historytype_count
    from PostHistory ph
    join PostHistoryTypes phr on phr.Id = ph.PostHistoryTypeId
),
vote_aggregate as (
    select
        p.Id as PostId,
        count(v.Id) filter (where v.VoteTypeId in (2,14,16)) as PositiveVotes,
        count(v.Id) filter (where v.VoteTypeId in (3,4,12)) as NegativeVotes,
        bool_and(v.UserId is not null) as AllUserVotesNotNull,
        min(v.CreationDate) as FirstVoteDate,
        max(v.CreationDate) as LastVoteDate,
        sum(v.BountyAmount) as TotalBounty,
        (case when sum(v.BountyAmount) > 0 then 1 else 0 end) as HasBountyFlag
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
featured_user_badges as (
    select
        b.UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 3 when b.Class = 2 then 2 else 1 end) as BadgeScore,
        count(DISTINCT b.Name) as DistinctBadgesCount,
        max(b.Date) as LatestBadgeDate,
        count(*) as TotalBadges
    from Badges b
    join Users u on u.Id = b.UserId
    group by b.UserId, u.DisplayName
),
duplicate_questions as (
    select distinct pl.PostId OriginalId, pl.RelatedPostId DuplicateOf
    from PostLinks pl
    where pl.LinkTypeId = 3
),
combined_data as (
    select
        fp.Id,
        fp.Title,
        fp.OwnerUserId,
        fp.OwnerUserName,
        fp.Score,
        fp.ViewCount,
        fp.Tags,
        fp.PositiveCommentCount,
        fp.UpVotesCount,
        fp.DownVotesCount,
        pah.PostHistoryTypeId,
        pah.HistoryTypeName,
        pah.historytype_count,
        vu.PositiveVotes,
        vu.NegativeVotes,
        vu.TotalBounty,
        fub.BadgeScore,
        fub.DistinctBadgesCount,
        fub.LatestBadgeDate,
        coalesce(dq.DuplicateOf, 0) as DuplicateQuestionId,
        tp.path_length,
        tp.tag
    from filtered_posts fp
    left join post_history_windows pah on pah.PostId = fp.Id
    left join vote_aggregate vu on vu.PostId = fp.Id
    left join featured_user_badges fub on fub.UserId = fp.OwnerUserId
    left join duplicate_questions dq on dq.OriginalId = fp.Id
    left join tag_paths tp on tp.post_id = fp.Id and tp.tag = unnest(string_to_array(fp.Tags, '><'))
    where fp.rn_desc_score <= 5
)
select *
from (
    select
        c.Id as PostId,
        c.Title,
        c.OwnerUserName,
        c.Score,
        c.ViewCount,
        c.Tags,
        c.PositiveCommentCount,
        c.UpVotesCount,
        c.DownVotesCount,
        c.HistoryTypeName,
        c.historytype_count,
        c.PositiveVotes,
        c.NegativeVotes,
        c.TotalBounty,
        c.BadgeScore,
        c.DistinctBadgesCount,
        c.LatestBadgeDate,
        c.DuplicateQuestionId,
        c.path_length,
        c.tag,
        dense_rank() over (partition by c.tag order by c.Score desc, c.ViewCount desc) AS RankedInTag,
        percentile_cont(0.5) within group (order by c.Score) over (partition by c.OwnerUserName) as MedianScoreByUser,
        concat(coalesce(nullif(c.OwnerUserName,''),'anonymous'), ' asks:', c.Title) as HighlightedTitle,
        case
            when c.DownVotesCount > c.UpVotesCount then 'Controversial'
            when c.Score > 50 and c.ViewCount > 10000 then 'High Impact'
            else 'Normal'
        end as ImpactCategory,
        case when c.TotalBounty > 0 then 'With Bounty' else 'No Bounty' end as BountyStatus
    from combined_data c
    where c.DuplicateQuestionId = 0 or c.DuplicateQuestionId is null
) final_view
where RankedInTag <= 10
order by RankedInTag, Score desc, ViewCount desc;