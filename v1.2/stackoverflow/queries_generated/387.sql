-- {"query": "387.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1941} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    where p.PostTypeId in (1,2)
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.Body as AnswerBody
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes cr on ph.Comment::int = cr.Id and ph.PostHistoryTypeId = 10
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
UserCommentStats as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctPostsCommented
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
UserVoteSummary as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
UserPostScoreRank as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.Score,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
UserTopPosts as (
    select
        upr.OwnerUserId,
        upr.PostId,
        upr.Score,
        p.Title,
        p.CreationDate
    from UserPostScoreRank upr
    join Posts p on p.Id = upr.PostId
    where upr.ScoreRank <= 3
),
CombinedUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TagBasedBadges,0) as TagBasedBadges,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(ucs.DistinctPostsCommented,0) as DistinctPostsCommented,
        coalesce(uvs.UpVotesCast,0) as UpVotesCast,
        coalesce(uvs.DownVotesCast,0) as DownVotesCast,
        coalesce(uvs.FavoritesCast,0) as FavoritesCast
    from Users u
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    left join UserCommentStats ucs on ucs.UserId = u.Id
    left join UserVoteSummary uvs on uvs.UserId = u.Id
)
select
    cuss.UserId,
    cuss.DisplayName,
    cuss.Reputation,
    cuss.GoldBadges,
    cuss.SilverBadges,
    cuss.BronzeBadges,
    cuss.TagBasedBadges,
    cuss.CommentCount,
    round(cuss.AvgCommentLength,2) as AvgCommentLength,
    cuss.DistinctPostsCommented,
    cuss.UpVotesCast,
    cuss.DownVotesCast,
    cuss.FavoritesCast,
    coalesce(qw.AnswerCount,0) as TotalAnswersToTopQuestions,
    coalesce(closedq.CloseReason, 'Not Closed') as LastClosedReason,
    coalesce(closedq.CloseDate, null) as LastClosedDate,
    string_agg(distinct rt.TagName, ', ') filter (where rt.Level = 1) as Level1Tags,
    string_agg(distinct rt.TagName, ', ') filter (where rt.Level = 2) as Level2Tags,
    string_agg(distinct rt.TagName, ', ') filter (where rt.Level = 3) as Level3Tags,
    utp.PostId as TopPostId,
    utp.Title as TopPostTitle,
    utp.Score as TopPostScore,
    utp.CreationDate as TopPostCreationDate
from CombinedUserStats cuss
left join (
    select
        q.OwnerUserId,
        count(a.Id) as AnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
    group by q.OwnerUserId
) qw on qw.OwnerUserId = cuss.UserId
left join (
    select distinct on (ph.PostId)
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes cr on ph.Comment::int = cr.Id and ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
) closedq on closedq.PostId = (
    select p.Id from Posts p where p.OwnerUserId = cuss.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1
)
left join RecursiveTagHierarchy rt on rt.TagName = any(string_to_array(coalesce((
    select p.Tags from Posts p where p.OwnerUserId = cuss.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1
),''), '><'))
left join UserTopPosts utp on utp.OwnerUserId = cuss.UserId
group by
    cuss.UserId,
    cuss.DisplayName,
    cuss.Reputation,
    cuss.GoldBadges,
    cuss.SilverBadges,
    cuss.BronzeBadges,
    cuss.TagBasedBadges,
    cuss.CommentCount,
    cuss.AvgCommentLength,
    cuss.DistinctPostsCommented,
    cuss.UpVotesCast,
    cuss.DownVotesCast,
    cuss.FavoritesCast,
    qw.AnswerCount,
    closedq.CloseReason,
    closedq.CloseDate,
    utp.PostId,
    utp.Title,
    utp.Score,
    utp.CreationDate
order by cuss.Reputation desc nulls last
limit 50;