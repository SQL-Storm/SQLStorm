-- {"query": "2314.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1500} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        0 as Level,
        cast(t.TagName as varchar(4000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        r.Level + 1,
        r.Path || '>' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.ExcerptPostId = r.Id
    where r.Level < 3
),
PostWithBadges as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(b.BadgeCount, 0) as BadgeCount
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select
            UserId,
            count(*) as BadgeCount
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    where p.PostTypeId in (1,2)
),
AnswerAcceptedInfo as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerUserId
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
UserActivityRanked as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as ActivityRank,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(b.Class) as HighestBadgeClass
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
CloseReasonLatest as (
    select distinct on (ph.PostId)
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    order by ph.PostId, ph.CreationDate desc
),
PostsWithCommentsAndVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.OwnerUserId,
        count(distinct c.Id) as CommentsCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        coalesce(crl.CloseReasonName, 'Open') as CloseStatus
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    left join CloseReasonLatest crl on crl.PostId = p.Id
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.OwnerUserId, crl.CloseReasonName
),
FilteredTags as (
    select
        rth.Id,
        rth.TagName,
        rth.Level,
        rth.Path
    from RecursiveTagHierarchy rth
    where rth.Level <= 2 and length(rth.TagName) > 2
)
select
    p.Id as PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentsCount,
    p.UpVotes,
    p.DownVotes,
    p.CloseStatus,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    u.HighestBadgeClass,
    subq.AverageScoreOverLast30Days,
    f.TagsExtracted,
    case
        when p.Score > subq.AverageScoreOverLast30Days then 'Above Average'
        when p.Score = subq.AverageScoreOverLast30Days then 'Average'
        else 'Below Average'
    end as ScorePerformance,
    windowRank.RankWithinScorePartition,
    string_agg(distinct ft.TagName, ', ') as RelatedTags
from PostsWithCommentsAndVotes p
left join Users u on u.Id = p.OwnerUserId
left join (
    select
        PostTypeId,
        avg(Score) filter (where CreationDate >= current_date - interval '30 days') as AverageScoreOverLast30Days
    from Posts
    group by PostTypeId
) subq on subq.PostTypeId = p.PostTypeId
left join (
    select
        p.Id,
        array_to_string(
            array(
                select unnest(string_to_array(
                    regexp_replace(coalesce(p.Tags, ''), '[<>]', ',', 'g'), ','
                ))
            ), ', '
        ) as TagsExtracted
    from Posts p
) f on f.Id = p.Id
left join FilteredTags ft on ft.TagName = any(string_to_array(regexp_replace(coalesce(p.Tags, ''), '[<>]', ''), '><'))
left join (
    select
        Id,
        rank() over (partition by Score order by CreationDate desc) as RankWithinScorePartition
    from Posts
) windowRank on windowRank.Id = p.Id
where p.PostTypeId = 1
and (
    p.Score > (
        select avg(Score) from Posts 
        where PostTypeId = 1 and CreationDate >= current_date - interval '180 days'
    )
    or p.ViewCount > 1000
)
group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.CommentsCount, p.UpVotes, p.DownVotes, p.CloseStatus, u.DisplayName, u.Reputation, u.HighestBadgeClass, subq.AverageScoreOverLast30Days, f.TagsExtracted, windowRank.RankWithinScorePartition
order by p.CreationDate desc
limit 100;