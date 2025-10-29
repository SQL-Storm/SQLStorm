-- {"query": "2926.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1389}
with RecursiveUserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        coalesce(badges.BadgeCount, 0) as BadgeCount,
        u.Reputation,
        row_number() over (order by u.Reputation desc, count(distinct p.Id) filter (where p.PostTypeId = 1) desc) as UserRank
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Comments c on c.UserId = u.Id
        left join (
            select UserId, count(*) as BadgeCount
            from Badges
            group by UserId
        ) badges on badges.UserId = u.Id
    where
        u.Reputation > 1000
    group by
        u.Id, u.DisplayName, badges.BadgeCount, u.Reputation
),
RankedPosts AS (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank,
        dense_rank() over (order by p.Score desc) as ScoreRank
    from
        Posts p
        left join Users u on u.Id = p.OwnerUserId
    where
        p.PostTypeId in (1,2)
        and p.Score is not null
),
HighScoreTopPosts AS (
    select *
    from RankedPosts
    where PostRank <= 3
),
PostCommentsAggregated AS (
    select
        p.Id as PostId,
        count(c.Id) as TotalComments,
        sum(case when c.UserId is not null then 1 else 0 end) as CommentsByRegistered,
        sum(case when c.UserId is null then 1 else 0 end) as CommentsByAnonymous,
        string_agg(distinct substring(c.Text from 1 for 20), ' | ') as SampleComments
    from
        Posts p
        left join Comments c on c.PostId = p.Id
    group by
        p.Id
),
DuplicateLinkCounts AS (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from
        PostLinks pl
        inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by
        pl.PostId
),
PostCloseReasons AS (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVoteCount
    from
        PostHistory ph
        inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where
        ph.PostHistoryTypeId = 10
    group by
        ph.PostId, crt.Name
),
UserBadgeCountsByClass AS (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from
        Badges
    group by UserId
),
UserVoteSummary AS (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast
    from
        Votes v
        inner join VoteTypes vt on vt.Id = v.VoteTypeId
    where
        v.UserId is not null
    group by v.UserId
)
select
    ua.UserRank, ua.UserId, ua.DisplayName,
    ua.Reputation,
    ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade,
    ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
    us.UpVotesCast, us.DownVotesCast, us.FavoritesCast,
    hp.Id as TopPostId,
    hp.PostTypeId,
    hp.Title,
    hp.CreationDate,
    hp.Score,
    hp.ViewCount,
    hp.Tags,
    hp.AnswerCount,
    hp.FavoriteCount,
    pcm.TotalComments,
    pcm.CommentsByRegistered,
    pcm.CommentsByAnonymous,
    pcm.SampleComments,
    dl.DuplicateCount,
    coalesce(pcr.CloseReasonName, 'Open') as RecentCloseReason,
    pcr.CloseVoteCount
from
    RecursiveUserActivity ua
    left join UserBadgeCountsByClass ubc on ubc.UserId = ua.UserId
    left join UserVoteSummary us on us.UserId = ua.UserId
    left join HighScoreTopPosts hp on hp.OwnerUserId = ua.UserId
    left join PostCommentsAggregated pcm on pcm.PostId = hp.Id
    left join DuplicateLinkCounts dl on dl.PostId = hp.Id
    left join PostCloseReasons pcr on pcr.PostId = hp.Id
where
    ua.UserRank <= 30
union
select
    null, u.Id, u.DisplayName,
    u.Reputation,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.FavoriteCount,
    0, 0, 0, null,
    0,
    'Unknown',
    0
from
    Users u
    inner join Posts p on p.OwnerUserId = u.Id
where
    u.Reputation < 100
    and p.PostTypeId = 1
    and p.CreationDate > (cast('2024-10-01' as date) - interval '30 days')
order by
    Reputation desc nulls last,
    Score desc nulls last,
    UserRank nulls last,
    TopPostId nulls last;