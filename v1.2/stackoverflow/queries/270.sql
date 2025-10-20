-- {"query": "270.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1541} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
TopPostsPerTag as (
    select
        Id,
        TagName,
        PostId,
        Score,
        ViewCount,
        CreationDate,
        OwnerUserId,
        DisplayName
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
PostVotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostWithVotesAndClose as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(pvs.UpVotes, 0) as UpVotes,
        coalesce(pvs.DownVotes, 0) as DownVotes,
        coalesce(pvs.Favorites, 0) as Favorites,
        coalesce(pvs.CloseVotes, 0) as CloseVotes,
        pcr.CloseReason,
        pcr.CloseDate
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostVotesSummary pvs on pvs.PostId = p.Id
    left join PostCloseReasons pcr on pcr.PostId = p.Id
    where p.PostTypeId = 1
),
RankedPosts as (
    select
        *,
        rank() over (partition by Tags order by Score desc, ViewCount desc) as RankByScore,
        dense_rank() over (order by CloseDate desc nulls last) as RankByCloseDate
    from PostWithVotesAndClose
),
FilteredPosts as (
    select *
    from RankedPosts
    where RankByScore <= 10
      and (CloseReason is null or CloseReason not in ('Duplicate', 'Off-topic'))
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
FinalUserStats as (
    select
        ua.*,
        ucs.CommentCount,
        ucs.AvgCommentLength,
        ucs.LastCommentDate,
        case when ua.Reputation > 10000 then 'Expert'
             when ua.Reputation > 1000 then 'Intermediate'
             else 'Beginner' end as UserLevel
    from UserActivity ua
    left join UserCommentStats ucs on ucs.UserId = ua.Id
)
select
    fp.Id as QuestionId,
    fp.Title,
    fp.Tags,
    fp.Score,
    fp.ViewCount,
    fp.UpVotes,
    fp.DownVotes,
    fp.Favorites,
    fp.CloseReason,
    fp.CloseDate,
    fp.OwnerUserId,
    fp.OwnerName,
    fus.Reputation,
    fus.UserLevel,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.QuestionCount,
    fus.AnswerCount,
    fus.MaxPostScore,
    fus.AvgPostScore,
    fus.CommentCount,
    fus.AvgCommentLength,
    fus.LastCommentDate,
    case
        when fp.CloseReason is not null then 'Closed'
        when fp.Favorites > 50 then 'Highly Favorited'
        when fp.Score > 100 then 'Highly Scored'
        else 'Normal'
    end as PostStatus,
    concat(
        'Tags: ',
        coalesce(fp.Tags, '<none>'),
        ' | Owner: ',
        coalesce(fp.OwnerName, 'anonymous'),
        ' | Score/View: ',
        cast(fp.Score as varchar),
        '/',
        cast(fp.ViewCount as varchar)
    ) as Summary
from FilteredPosts fp
left join FinalUserStats fus on fus.Id = fp.OwnerUserId
where fp.CreationDate > cast('2024-10-01' as date) - interval '1 year'
order by fp.Score desc, fp.ViewCount desc
limit 50;