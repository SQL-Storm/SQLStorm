-- {"query": "1141.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1204} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count as TagCount,
        array_agg(distinct p.Id) filter (where p.Id is not null) as PostIds
    from Tags t
    left join Posts p on p.Tags like ('%<' || t.TagName || '>%')
    group by t.Id, t.TagName, t.Count

    union all

    select
        rt.Id,
        rt.TagName,
        rt.TagCount,
        rt.PostIds || array_agg(distinct pl.RelatedPostId)
    from RecursiveTagCounts rt
    join PostLinks pl on pl.PostId = any(rt.PostIds) and pl.LinkTypeId = 1
    group by rt.Id, rt.TagName, rt.TagCount, rt.PostIds
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersProvided,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.Score),0) as VoteBalance,
        avg(rnk.ScoreRank) as AvgScoreRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    left join Comments c on c.UserId = u.Id
    left join (
      select PostId, Score,
        rank() over (partition by PostTypeId order by Score desc nulls last) as ScoreRank
      from Posts
      where PostTypeId in (1, 2)
    ) rnk on rnk.PostId = p.Id
    left join (
        select PostId, sum(case when VoteTypeId = 2 then 1 when VoteTypeId = 3 then -1 else 0 end) as Score
        from Votes
        group by PostId
    ) vb on vb.PostId = p.Id
    group by u.Id, u.DisplayName
),
BadgedUsers as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        bool_or(b.TagBased = 1) as HasTagBasedBadges
    from Badges b
    group by b.UserId
),
ComplexPosts as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        pt.Name as PostType,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PreviousPostScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextPostScore,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        coalesce((
            select count(*)
            from Comments c2
            where c2.PostId = p.Id and c2.Score > 0
        ), 0) as PositiveComments,
        coalesce((
            select count(*)
            from Votes v2
            where v2.PostId = p.Id and v2.VoteTypeId = 2
        ), 0) as UpVotes
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId
    where p.PostTypeId in (1, 2) and p.Score is not null
),
FilteredPosts as (
    select
        cp.*,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        bu.GoldBadges,
        bu.SilverBadges,
        bu.BronzeBadges,
        bu.HasTagBasedBadges
    from ComplexPosts cp
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = cp.Id)
    left join BadgedUsers bu on bu.UserId = u.Id
    where cp.ScoreRank <= 100
)
select distinct
    fp.Id as PostId,
    fp.Title,
    fp.PostType,
    fp.Score,
    fp.ViewCount,
    fp.Tags,
    length(fp.Tags) - length(replace(fp.Tags, '<', '')) as TagCount,
    fp.PreviousPostScore,
    fp.NextPostScore,
    fp.PositiveComments,
    fp.UpVotes,
    fp.DisplayName as OwnerName,
    fp.Reputation as OwnerReputation,
    fp.Location as OwnerLocation,
    fp.GoldBadges,
    fp.SilverBadges,
    fp.BronzeBadges,
    fp.HasTagBasedBadges,
    ua.QuestionsAsked,
    ua.AnswersProvided,
    ua.CommentsMade,
    ua.VoteBalance,
    ua.AvgScoreRank,
    rtc.TagName,
    rtc.TagCount
from FilteredPosts fp
left join UserActivity ua on ua.UserId = (select OwnerUserId from Posts where Id = fp.Id)
left join RecursiveTagCounts rtc on rtc.TagName = any(string_to_array(
    substring(fp.Tags from 2 for char_length(fp.Tags) - 2)
    , '><'))
where (fp.Score > coalesce(fp.PreviousPostScore, 0) or fp.PositiveComments > 5)
and (ua.Reputation > 500 or fp.ViewCount > 10000)
order by fp.Score desc, ua.Reputation desc
limit 50;