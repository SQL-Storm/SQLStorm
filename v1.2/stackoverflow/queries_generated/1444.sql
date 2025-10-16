-- {"query": "1444.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1720} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.Title, p.OwnerUserId, p.Score, p.CreationDate, p.AcceptedAnswerId,
        1 as Depth,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
    union all
    select p2.Id, p2.PostTypeId, p2.Title, p2.OwnerUserId, p2.Score, p2.CreationDate, p2.AcceptedAnswerId,
        rp.Depth + 1,
        rp.Path || p2.Id
    from RecursivePosts rp
    join Posts p2 on p2.ParentId = rp.Id
    where p2.Id <> all(rp.Path) and rp.Depth < 5
),
AggBadges as (
    select b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBased,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
VoteStats as (
    select v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.VoteTypeId IN (8,9) then Coalesce(v.BountyAmount, 0) else 0 end) as TotalBounty,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserRecentActivities as (
    select *,
        row_number() over (partition by ua.UserId order by ua.ActivityDate desc) as rn
    from (
        select UserId, CreationDate as ActivityDate, 'Post' as ActivityType from Posts where OwnerUserId is not null
        union all
        select UserId, CreationDate as ActivityDate, 'Comment' as ActivityType from Comments
        union all
        select UserId, CreationDate as ActivityDate, 'Badge' as ActivityType from Badges
    ) ua
),
RecentUserActivities as (
    select UserId, ActivityDate, ActivityType
    from UserRecentActivities
    where rn <= 5
),
ClosedQuestionInfo as (
    select p.Id as QuestionId, p.Title, p.OwnerUserId, p.Score,
        cht.Name as CloseReason,
        ph.CreationDate as ClosedDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where p.PostTypeId = 1 and ph.Id is not null
),
QuestionDuplicates as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate,
        q.Title as QuestionTitle,
        dup.Title as DuplicateTitle
    from PostLinks pl
    join Posts q on q.Id = pl.PostId
    join Posts dup on dup.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserRanks as (
    select u.Id, u.DisplayName, u.Reputation,
       rank() over (order by u.Reputation desc, u.CreationDate) as ReputationRank,
       dense_rank() over (partition by u.Location order by u.Reputation desc nulls last) as LocationTopRank
    from Users u
    where u.Location is not null
),
TagStringSplit as (
    select
      p.Id as PostId,
      unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) -2), '><')) as Tag
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
),
TopTagsByUsage as (
    select Tag, count(*) as UseCount
    from TagStringSplit
    group by Tag
    having count(*) > 500
    order by count(*) desc
    limit 10
),
PostsWithTopTags as (
    select distinct p.*
    from Posts p
    join TagStringSplit ts on ts.PostId = p.Id
    join TopTagsByUsage ttu on ttu.Tag = ts.Tag
),
BadgesOnTopTagUsers as (
    select b.UserId, ttu.Tag, count(*) as BadgeCount
    from Badges b
    join TagStringSplit ts on ts.PostId in (select Id from Posts where OwnerUserId = b.UserId)
    join TopTagsByUsage ttu on ttu.Tag = ts.Tag
    where b.UserId is not null
    group by b.UserId, ttu.Tag
    having count(*) > 5
),
FinalSelection as (
    select distinct rp.Id as PostId,
        rp.Title,
        rp.OwnerUserId,
        u.DisplayName as OwnerName,
        rp.Score, rp.CreationDate,
        ab.GoldBadges, ab.SilverBadges, ab.BronzeBadges, ab.HasTagBased, ab.LastBadgeDate,
        vs.UpVotes, vs.DownVotes, vs.TotalBounty, vs.LastVoteDate,
        u.LastAccessDate,
        (select count(*) from Comments c where c.PostId = rp.Id) as CommentCount,
        (select count(*) from Posts p2 where p2.ParentId = rp.Id) as AnswerCount,
        lct.Name as LinkTypeName,
        qd.DuplicateTitle,
        cqi.CloseReason, cqi.ClosedDate
    from RecursivePosts rp
    join Users u on u.Id = rp.OwnerUserId
    left join AggBadges ab on ab.UserId = rp.OwnerUserId
    left join VoteStats vs on vs.PostId = rp.Id
    left join PostLinks pl on pl.PostId = rp.Id
    left join LinkTypes lct on lct.Id = pl.LinkTypeId
    left join QuestionDuplicates qd on qd.PostId = rp.Id and qd.CreationDate = (
        select max(CreationDate) from PostLinks where PostId = rp.Id and LinkTypeId = 3
    )
    left join ClosedQuestionInfo cqi on cqi.QuestionId = rp.Id
    where rp.Depth = 1
)
select
    f.PostId,
    f.Title,
    f.OwnerUserId,
    f.OwnerName,
    f.Score,
    f.CommentCount,
    f.AnswerCount,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    case
        when f.HasTagBased then 'Yes'
        else 'No'
    end as HasTagBasedBadges,
    f.LastBadgeDate,
    f.UpVotes,
    f.DownVotes,
    f.TotalBounty,
    f.LastVoteDate,
    f.LastAccessDate,
    f.LinkTypeName,
    coalesce(f.DuplicateTitle, 'N/A') as DuplicateOf,
    coalesce(f.CloseReason, 'Open') as CloseReason,
    f.ClosedDate,
    DenseRank() over (order by f.Score desc nulls last) as ScoreRank,
    DenseRank() over (partition by f.CloseReason order by f.CreationDate DESC nulls last) as RecentRankPerCloseReason,
    substring(f.Title from '.{10}') || '...' as TitleSnippet,
    case when f.CommentsCount > f.AnswerCount then 'MoreComments' else 'MoreAnswers' end as CommentsVsAnswers,
    coalesce(cqi.ClosedDate > now() - interval '90 days', false) as ClosedRecently
from FinalSelection f
left join ClosedQuestionInfo cqi on cqi.QuestionId = f.PostId
where f.Score > 5
order by f.Score desc nulls last, f.CreationDate desc
limit 50;