-- {"query": "450.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1523} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        ph.Id as PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.Comment as HistoryComment,
        row_number() over (partition by p.Id order by ph.CreationDate desc nulls last) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    where u.Reputation > 1000
),
LatestPostHistory as (
    select
        UserId,
        PostId,
        PostTypeId,
        Score,
        ViewCount,
        PostCreationDate,
        PostHistoryTypeId,
        HistoryDate,
        HistoryComment
    from RecursiveUserActivity
    where rn = 1
),
UserBadgeStats as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as UniqueBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(a.MinAnswerScore, 0) as MinAnswerScore
    from Posts q
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            avg(Score) as AvgAnswerScore,
            max(Score) as MaxAnswerScore,
            min(Score) as MinAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    where q.PostTypeId = 1
),
UserCommentActivity as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as TotalComments,
        count(distinct c.PostId) as CommentedPosts,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score is null then 0 else c.Score end) as TotalCommentScore
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
TopTagsPerUser as (
    select distinct
        u.Id as UserId,
        t.TagName,
        t.Count,
        row_number() over (partition by u.Id order by t.Count desc) as TagRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as t(TagName)
    join Tags t on t.TagName = t.TagName
    where u.Reputation > 500
),
UserTopTags as (
    select UserId, TagName
    from TopTagsPerUser
    where TagRank <= 3
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserVoteStats as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(*) filter (where vt.Name = 'Close') as CloseVotesCast,
        count(*) filter (where vt.Name = 'Reopen') as ReopenVotesCast
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.UniqueBadges,
    ub.LastBadgeDate,
    ua.TotalComments,
    ua.CommentedPosts,
    ua.LastCommentDate,
    ua.TotalCommentScore,
    uv.UpVotesCast,
    uv.DownVotesCast,
    uv.FavoritesCast,
    uv.CloseVotesCast,
    uv.ReopenVotesCast,
    string_agg(distinct utt.TagName, ', ') as TopTags,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.QuestionDate,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    dpl.PostTitle as DuplicatePostTitle,
    dpl.RelatedPostTitle as DuplicateRelatedPostTitle,
    dpl.CreationDate as DuplicateLinkDate
from Users u
left join UserBadgeStats ub on ub.UserId = u.Id
left join UserCommentActivity ua on ua.UserId = u.Id
left join UserVoteStats uv on uv.UserId = u.Id
left join UserTopTags utt on utt.UserId = u.Id
left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
left join PostAnswerStats qas on qas.QuestionId = p.Id
left join DuplicateLinks dpl on dpl.PostId = p.Id
where u.Reputation > 1000
group by
    u.Id, u.DisplayName, u.Reputation,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.UniqueBadges, ub.LastBadgeDate,
    ua.TotalComments, ua.CommentedPosts, ua.LastCommentDate, ua.TotalCommentScore,
    uv.UpVotesCast, uv.DownVotesCast, uv.FavoritesCast, uv.CloseVotesCast, uv.ReopenVotesCast,
    qas.QuestionId, qas.Title, qas.QuestionDate, qas.QuestionScore, qas.QuestionViews,
    qas.AnswerCount, qas.AvgAnswerScore, qas.MaxAnswerScore, qas.MinAnswerScore,
    dpl.PostTitle, dpl.RelatedPostTitle, dpl.CreationDate
order by u.Reputation desc
limit 100;