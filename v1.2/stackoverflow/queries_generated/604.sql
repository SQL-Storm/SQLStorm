-- {"query": "604.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1586} 
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(b.Class),0) as BadgeScore,
        row_number() over (order by count(b.Id) desc, u.Reputation desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopUsersWithPosts as (
    select
        ubc.UserId,
        ubc.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.BadgeScore,
        ubc.BadgeRank,
        count(p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.CreationDate) as LatestPostDate
    from UserBadgeCounts ubc
    left join Posts p on p.OwnerUserId = ubc.UserId
    where ubc.BadgeRank <= 100
    group by ubc.UserId, ubc.DisplayName, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.BadgeScore, ubc.BadgeRank
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(c.Id) filter (where c.UserId is not null) as CommentCount,
        string_agg(distinct coalesce(c.Text, '') , ' | ') filter (where c.Text is not null) as CommentsTexts
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Comments c on c.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags, a.Id, a.OwnerUserId, a.Score, a.CreationDate
),
TopAnswersPerQuestion as (
    select
        QuestionId,
        Title,
        OwnerUserId,
        QuestionDate,
        QuestionScore,
        ViewCount,
        Tags,
        AnswerId,
        AnswerUserId,
        AnswerScore,
        AnswerDate,
        CommentCount,
        CommentsTexts
    from QuestionAnswerStats
    where AnswerRank = 1
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        avg(p.Score) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as AvgScoreLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.CreationDate >= (current_date - interval '365 days')
),
DuplicateQuestionLinks as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^[0-9]+$'
    group by ph.PostId, crt.Name
)
select
    u.UserId,
    u.DisplayName,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.BadgeScore,
    u.BadgeRank,
    u.TotalPosts,
    u.QuestionsCount,
    u.AnswersCount,
    round(u.AvgPostScore,2) as AvgPostScore,
    to_char(u.LatestPostDate, 'YYYY-MM-DD') as LatestPostDate,
    tq.Title as TopQuestionTitle,
    tq.QuestionScore,
    tq.ViewCount as QuestionViews,
    replace(coalesce(tq.Tags,'<no tags>'), '><', ', ') as ParsedTags,
    ta.AnswerScore as TopAnswerScore,
    ta.AnswerDate as TopAnswerDate,
    ta.CommentCount as TopQuestionCommentCount,
    left(coalesce(ta.CommentsTexts, ''), 200) as SampleComments,
    da.DuplicateQuestionId,
    da.OriginalQuestionId,
    da.DuplicateTitle,
    da.OriginalTitle,
    da.LinkCreationDate,
    crc.CloseReason,
    crc.CloseVotesCount,
    ua.PostsLast30Days,
    round(ua.AvgScoreLast30Days,2) as AvgScoreLast30Days
from TopUsersWithPosts u
left join lateral (
    select q.Title, q.Score as QuestionScore, q.ViewCount, q.Tags
    from Posts q
    where q.OwnerUserId = u.UserId and q.PostTypeId = 1
    order by q.Score desc nulls last, q.CreationDate desc
    limit 1
) tq on true
left join lateral (
    select a.AnswerScore, a.AnswerDate, a.CommentCount, a.CommentsTexts
    from TopAnswersPerQuestion a
    where a.OwnerUserId = u.UserId and a.AnswerUserId = u.UserId
    order by a.AnswerScore desc nulls last
    limit 1
) ta on true
left join DuplicateQuestionLinks da on da.DuplicateQuestionId = tq.QuestionId
left join CloseReasonsCount crc on crc.PostId = tq.QuestionId
left join lateral (
    select ua.PostsLast30Days, ua.AvgScoreLast30Days
    from UserActivityWindow ua
    where ua.UserId = u.UserId
    order by ua.CreationDate desc
    limit 1
) ua on true
where u.TotalPosts > 50
order by u.BadgeRank
limit 50;