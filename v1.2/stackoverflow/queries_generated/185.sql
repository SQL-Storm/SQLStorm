-- {"query": "185.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1458} 
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
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    where not t2.TagName = any(r.Path)
    and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        coalesce(u.AboutMe, '') as AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 10
      and q.ViewCount > 1000
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    group by ph.PostId, crt.Name
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctPostsCommented
    from Comments c
    group by c.UserId
),
UserVoteStats as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.WebsiteUrl,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ps.QuestionCount,
    ps.AnswerCount,
    ps.AvgPostScore,
    ps.MaxPostScore,
    ps.TotalQuestionViews,
    coalesce(ucs.CommentCount, 0) as CommentCount,
    coalesce(ucs.AvgCommentLength, 0) as AvgCommentLength,
    coalesce(ucs.DistinctPostsCommented, 0) as DistinctPostsCommented,
    coalesce(uvs.UpVotesCast, 0) as UpVotesCast,
    coalesce(uvs.DownVotesCast, 0) as DownVotesCast,
    coalesce(uvs.FavoritesCast, 0) as FavoritesCast,
    tq.QuestionId,
    tq.Title as TopQuestionTitle,
    tq.QuestionScore,
    tq.QuestionViews,
    tq.Tags as QuestionTags,
    tq.AnswerId,
    tq.AnswerScore,
    tq.AnswerCreationDate,
    tq.AnswerOwnerUserId,
    tq.AnswerOwnerDisplayName,
    crc.CloseReason,
    crc.CloseCount,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath
from UserActivity ua
left join PostScoreStats ps on ps.OwnerUserId = ua.UserId
left join UserCommentStats ucs on ucs.UserId = ua.UserId
left join UserVoteStats uvs on uvs.UserId = ua.UserId
left join TopQuestionsWithAnswers tq on tq.AnswerOwnerUserId = ua.UserId and tq.AnswerRank = 1
left join CloseReasonCounts crc on crc.PostId = tq.QuestionId
left join RecursiveTagHierarchy rh on rh.TagName = any(string_to_array(coalesce(tq.Tags, ''), '><'))
where ua.Reputation > 1000
order by ua.Reputation desc, ps.TotalQuestionViews desc
limit 100;