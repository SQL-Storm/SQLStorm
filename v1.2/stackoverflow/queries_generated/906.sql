-- {"query": "906.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1625} 
with RecursiveUserDescendants as (
    -- Recursive CTE to find users who have replied to a user's questions (depth 1)
    select distinct u.Id as RootUserId, p.OwnerUserId as DescendantUserId, 1 as Depth
    from Users u
    join Posts p on p.ParentId is null and p.OwnerUserId is not null
    join Posts a on a.ParentId = p.Id and a.OwnerUserId is not null
    where u.Id = p.OwnerUserId
    union all
    select rud.RootUserId, p.OwnerUserId, rud.Depth + 1
    from RecursiveUserDescendants rud
    join Posts p on p.ParentId is not null and p.OwnerUserId is not null and p.ParentId in (
        select Id from Posts where OwnerUserId = rud.DescendantUserId
    )
    where rud.Depth < 2
),
UserBadgeStats as (
    select
        u.Id as UserId,
        count(distinct b.Id) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
PostEngagement as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.CommentCount,0) as CommentCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as RankByScore,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    where p.OwnerUserId is not null
),
PostHistoryCloseInfo as (
    select 
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as FirstCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as LastReopenDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    u.WebsiteUrl,
    u.Views,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    coalesce(peq.Score, 0) as HighestQuestionScore,
    coalesce(pea.Score, 0) as HighestAnswerScore,
    -- Calculate average score difference between consecutive posts per user
    avg((pe.Score - coalesce(pe.PrevScore, 0))::float) over (partition by u.Id) as AvgScoreDiffBetweenPosts,
    -- Aggregate number of replies from other users up to depth 2
    (select count(distinct rud.DescendantUserId)
     from RecursiveUserDescendants rud
     where rud.RootUserId = u.Id and rud.DescendantUserId <> u.Id) as DistinctRespondersWithin2Levels,
    -- Most common close reason for user's questions (if any)
    crt.Name as MostCommonCloseReason,
    -- Concatenate distinct badge names the user has earned separated by '|', truncated to 200 chars
    substring(string_agg(distinct b.Name, ' | ' order by b.Date desc) from 1 for 200) as BadgeNames,
    -- String expression example: concatenation of user's top 3 tags from their questions
    substring(
        (
            select string_agg(tag, ', ' order by question_count desc)
            from (
                select unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) as tag,
                    count(*) as question_count
                from Posts p
                where p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
                group by tag
                order by question_count desc
                limit 3
            ) t
        )
    from 1 for 100) as Top3Tags,
    -- Using set operator: union of user and last editor display names for top scoring answers
    (
        select string_agg(distinct name, ', ')
        from (
            select p.OwnerDisplayName as name from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2 order by p.Score desc limit 5
            union
            select p.LastEditorDisplayName as name from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2 and p.LastEditorDisplayName is not null order by p.Score desc limit 5
        ) combined
        where name is not null and name <> ''
    ) as TopAnswerContributors
from Users u
left join UserBadgeStats ub on ub.UserId = u.Id
left join UserActivitySummary uas on uas.UserId = u.Id
left join PostEngagement pe on pe.OwnerUserId = u.Id
left join PostEngagement peq on peq.OwnerUserId = u.Id and peq.PostTypeId = 1 and peq.RankByScore = 1
left join PostEngagement pea on pea.OwnerUserId = u.Id and pea.PostTypeId = 2 and pea.RankByScore = 1
left join PostHistoryCloseInfo phci on phci.PostId in (
    select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1
)
left join CloseReasonTypes crt on crt.Id = phci.CloseReasonId
where u.Reputation > 1000
order by u.Reputation desc
limit 50;