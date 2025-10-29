-- {"query": "2179.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1654} 
with RecursiveUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(nullif(u.Location, ''), 'Unknown') as Location,
        coalesce(u.WebsiteUrl, 'N/A') as WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        (
            select count(*)
            from Posts p
            where p.OwnerUserId = u.Id
              and p.PostTypeId = 1
              and p.CreationDate > current_date - interval '365 day'
        ) as QuestionsLastYear,
        (
            select count(*)
            from Posts p
            where p.OwnerUserId = u.Id
              and p.PostTypeId = 2
        ) as AnswersTotal,
        (
            select max(v.CreationDate)
            from Votes v
            join Posts vp on vp.Id = v.PostId
            where v.UserId = u.Id
              and vp.PostTypeId = 1
              and v.VoteTypeId = 2
        ) as LastUpvoteOnQuestion
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by u.Id
),
PostsWithDetails as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        u.DisplayName as OwnerDisplayName,
        case when p.PostTypeId = 1 then coalesce(p.AnswerCount, 0) else null end as AnswerCount,
        count(com.Id) filter (where com.CreationDate > current_date - interval '30 day') as RecentCommentsCount,
        count(vt.Id) filter (where vt.VoteTypeId = 2 and vt.CreationDate > current_date - interval '7 day') as RecentUpvotes,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate desc) as NextPostScore,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate asc) as PrevPostScore
    from
        Posts p
        left join Users u on u.Id = p.OwnerUserId
        left join Comments com on com.PostId = p.Id
        left join Votes vt on vt.PostId = p.Id
    group by p.Id, u.DisplayName
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name ILIKE '%Duplicate%'
),
UserPostsWithDupes as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        coalesce(d.RelatedPostId, -1) as DuplicateOfPostId,
        case when d.RelatedPostId is not null then 1 else 0 end as IsDuplicate,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId
    from Posts p
    left join DuplicateLinks d on d.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
),
QuestionsWithCloseReason as (
    select
        p.Id,
        p.Title,
        p.Tags,
        ph.Comment::int as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate -- from PostHistory 10 = Post Closed
    from
        Posts p
        left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
),
TopTagsByAnswerScore as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
        sum(coalesce(a.Score, 0)) as TotalAnswerScore,
        count(a.Id) as AnswerCount
    from
        Posts p
        left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by Tag
    having count(a.Id) > 5
),
TagWithRanks as (
    select
        Tag,
        TotalAnswerScore,
        AnswerCount,
        rank() over (order by TotalAnswerScore desc) as ScoreRank,
        rank() over (order by AnswerCount desc) as AnswerCountRank
    from TopTagsByAnswerScore
),
FinalAggregated as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.QuestionsLastYear,
        u.AnswersTotal,
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.RecentCommentsCount,
        p.RecentUpvotes,
        dup.IsDuplicate,
        dup.DuplicateOfPostId,
        q.CloseReasonName,
        q.CloseDate,
        t.Tag,
        t.TotalAnswerScore,
        t.AnswerCount as TagAnswerCount,
        t.ScoreRank,
        t.AnswerCountRank,
        u.LastUpvoteOnQuestion,
        -- Complex calculated field combining several conditions with null logic
        case
            when p.PostTypeId = 1 and p.ClosedDate is null and p.AnswerCount >= 3 then
                (p.Score * 1.2 + coalesce(p.RecentUpvotes, 0) * 0.8) / nullif(greatest(p.ViewCount, 1), 0)
            when p.PostTypeId = 2 then
                (p.Score + coalesce(p.RecentUpvotes, 0)) * 1.1
            else 0
        end as PerformanceIndex,
        -- String concatenation with null-safe coalesce and substring
        coalesce(substr(p.Title, 1, 50), 'No Title') || 
        ' | Owner: ' || coalesce(u.DisplayName, 'Anonymous') ||
        ' | Location: ' || coalesce(u.Location, 'N/A') as PostSummary
    from
        RecursiveUserActivity u
        join PostsWithDetails p on p.OwnerUserId = u.Id
        left join UserPostsWithDupes dup on dup.PostId = p.Id
        left join QuestionsWithCloseReason q on q.Id = p.Id
        left join Lateral (
            select tt.Tag, tt.TotalAnswerScore, tt.AnswerCount, tt.ScoreRank, tt.AnswerCountRank
            from TagWithRanks tt
            where tt.Tag = any(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'))
            order by tt.TotalAnswerScore desc
            limit 1
        ) t on true
)
select *
from FinalAggregated
where PerformanceIndex > 0
order by PerformanceIndex desc, Reputation desc
limit 100;