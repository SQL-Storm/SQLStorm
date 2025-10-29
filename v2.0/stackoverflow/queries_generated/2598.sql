-- {"query": "2598.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1482} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteTypeId = 2::smallint)::int, 0) as UpModVotesReceived,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc nulls last) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = any(array(
        select p2.Id from Posts p2 where p2.OwnerUserId = u.Id
    ))
    group by u.Id
), RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as PostRankByType,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate) as OwnerPostSequence,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostScore
    from Posts p
    where p.PostTypeId in (1,2)
), TagExtracts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.Tags is not null and p.Tags <> ''
), BadgeAggs as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), LatestHistoryPerPost as (
    select ph.PostId, max(ph.CreationDate) as LastHistoryDate
    from PostHistory ph
    group by ph.PostId
), CloseReasonsCount as (
    select ph.PostId,
           count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
           count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes
    from PostHistory ph
    group by ph.PostId
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    where pl.LinkTypeId = 3
), QuestionAnswerStats as (
    select q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        count(a.Id) as AnswerCountPerQuestion,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        bool_or(a.Score > q.Score) as AnyAnswerBetterScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(b.GoldBadges,0) as GoldBadges,
    coalesce(b.SilverBadges,0) as SilverBadges,
    coalesce(b.BronzeBadges,0) as BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    ua.UpModVotesReceived,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.AnswerCountPerQuestion,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.AnyAnswerBetterScore,
    rh.LastHistoryDate,
    crc.CloseVotes,
    crc.ReopenVotes,
    string_agg(distinct te.TagName, ',' order by te.TagName) as UserQuestionTags,
    p.PostId,
    p.PostTypeId,
    p.Score as PostScore,
    p.ViewCount as PostViewCount,
    p.Tags as PostTags,
    p.PostRankByType,
    p.OwnerPostSequence,
    p.PrevPostScore,
    p.NextPostScore,
    dup.RelatedPostId as DuplicateOfPostId
from Users u
inner join RecursiveUserActivity ua on ua.UserId = u.Id
left join BadgeAggs b on b.UserId = u.Id
left join QuestionAnswerStats qas on qas.OwnerUserId = u.Id
left join RankedPosts p on p.OwnerUserId = u.Id and p.PostRankByType <= 5
left join LatestHistoryPerPost rh on rh.PostId = p.Id
left join CloseReasonsCount crc on crc.PostId = p.Id
left join TagExtracts te on te.PostId = p.Id
left join DuplicateLinks dup on dup.PostId = p.Id
where u.Reputation > (
    select avg(Reputation) from Users
)
and (
    p.Score > 10 or
    p.ViewCount > 1000 or
    crc.CloseVotes > 0
)
group by 
    u.Id, u.DisplayName, u.Reputation,
    b.GoldBadges, b.SilverBadges, b.BronzeBadges,
    ua.QuestionCount, ua.AnswerCount, ua.CommentCount, ua.Views, ua.UpVotes, ua.DownVotes, ua.UpModVotesReceived,
    qas.QuestionId, qas.Title, qas.AnswerCountPerQuestion, qas.AvgAnswerScore, qas.MaxAnswerScore, qas.AnyAnswerBetterScore,
    rh.LastHistoryDate,
    crc.CloseVotes, crc.ReopenVotes,
    p.PostId, p.PostTypeId, p.Score, p.ViewCount, p.Tags, p.PostRankByType, p.OwnerPostSequence, p.PrevPostScore, p.NextPostScore,
    dup.RelatedPostId
order by u.Reputation desc, p.Score desc nulls last, p.ViewCount desc nulls last
limit 100;