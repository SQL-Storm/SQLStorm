-- {"query": "2742.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1492} 
with RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as Rank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        avg(coalesce(p.Score, 0)) as AvgPostScore,
        count(distinct p.Id) as PostsCount
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestions as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName,
        u.Reputation,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserPostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10
),
CloseReasonsCount as (
    select 
        c.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as ClosedPostCount
    from PostHistory c
    join CloseReasonTypes crt on crt.Id = cast(c.Comment as int)
    where c.PostHistoryTypeId = 10
    group by c.Comment, crt.Name
),
AnswerStats as (
    select 
        p.ParentId as QuestionId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct ph.PostId) as EditsCount,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionWithLinks as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        array_agg(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedPosts,
        array_agg(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicatePosts
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Score, q.ViewCount
),
FinalSelection as (
    select 
        q.QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        coalesce(a.UpVotes,0) as AnswerUpVotes,
        coalesce(a.DownVotes,0) as AnswerDownVotes,
        coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(u.DisplayName, 'unknown') as OwnerName,
        coalesce(u.Reputation, 0) as OwnerRep,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        string_agg(distinct rtrim(trim(splitted_tags), '>'), ' | ') as NormalizedTags,
        array_length(q.LinkedPosts,1) as LinkedCount,
        array_length(q.DuplicatePosts,1) as DuplicateCount,
        crc.ClosedPostCount as CloseReasonFrequency
    from QuestionWithLinks q
    left join AnswerStats a on a.QuestionId = q.QuestionId
    left join Posts p on p.Id = q.QuestionId
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeStats ub on ub.UserId = u.Id
    left join LATERAL unnest(string_to_array(coalesce(p.Tags,''), '><')) t(splitted_tags) on true
    left join CloseReasonsCount crc on crc.CloseReasonId = (
        select ph.Comment
        from PostHistory ph
        where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        order by ph.CreationDate desc limit 1
    )
    group by q.QuestionId, q.Title, q.Score, q.ViewCount, a.UpVotes, a.DownVotes, a.AvgAnswerScore,
        u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, 
        q.LinkedPosts, q.DuplicatePosts, crc.ClosedPostCount
)
select 
    fs.QuestionId,
    fs.Title,
    fs.Score,
    fs.ViewCount,
    fs.AnswerUpVotes,
    fs.AnswerDownVotes,
    fs.AvgAnswerScore,
    fs.OwnerName,
    fs.OwnerRep,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.NormalizedTags,
    fs.LinkedCount,
    fs.DuplicateCount,
    fs.CloseReasonFrequency,
    rank() over (order by fs.Score desc, fs.ViewCount desc) as PopularityRank,
    lag(fs.Score) over (order by fs.Score desc) as PreviousScore,
    lead(fs.Score) over (order by fs.Score desc) as NextScore,
    case 
        when fs.CloseReasonFrequency is null then 'Open'
        when fs.CloseReasonFrequency > 10 then 'Frequently Closed'
        else 'Occasionally Closed'
    end as CloseStatus,
    substring(fs.Title from '(\w{4,})') as SampleWordInTitle,
    length(fs.NormalizedTags) - length(replace(fs.NormalizedTags,'|','')) + 1 as TagCount
from FinalSelection fs
where fs.Score > 50 or fs.ViewCount > 1000
order by PopularityRank
limit 50;