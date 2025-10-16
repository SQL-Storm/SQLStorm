-- {"query": "552.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1563} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, 1 as Level, array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select t.Id, t.TagName, t.Count, r.Level + 1, r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and not t.Id = any(r.Path)
    where r.Level < 3
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.CreationDate) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostWithBadges as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate,
        row_number() over (partition by p.Id order by b.Class) as BadgeRank
    from Posts p
    left join Badges b on b.UserId = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
TopBadgedPosts as (
    select *
    from PostWithBadges
    where BadgeRank = 1
),
PostCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName,'[deleted]'), ', ' order by c.CreationDate desc) as Commenters
    from Comments c
    group by c.PostId
),
CloseReasonStats as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount,
        max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.Score > 5 then 1 else 0 end) as HighScoreAnswers
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionAnswerVotes as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        v.VoteTypeId,
        count(*) as VoteCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = a.Id and v.VoteTypeId in (2,3)
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Score, a.Id, a.Score, v.VoteTypeId
),
UserTagEngagement as (
    select
        u.Id as UserId,
        u.DisplayName,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        count(*) as PostsWithTag,
        sum(p.Score) as TotalScore
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    group by u.Id, u.DisplayName, Tag
),
UserTopTags as (
    select distinct on (UserId) UserId, DisplayName, Tag, PostsWithTag, TotalScore
    from UserTagEngagement
    order by UserId, TotalScore desc, PostsWithTag desc
)
select
    ua.UserRank,
    ua.DisplayName as User,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalVotesReceived,
    coalesce(asn.AnswerCount,0) as TotalAnswers,
    coalesce(asn.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(asn.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(asn.HighScoreAnswers,0) as HighScoreAnswers,
    coalesce(crs.CloseReason, 'No Close') as MostCommonCloseReason,
    coalesce(crs.CloseCount, 0) as CloseVotes,
    coalesce(pc.CommentCount, 0) as CommentsOnPosts,
    coalesce(pc.LastCommentDate, '1970-01-01') as LastCommentDate,
    coalesce(pc.Commenters, '') as RecentCommenters,
    coalesce(ut.Tag, '[No Top Tag]') as TopTag,
    coalesce(ut.PostsWithTag, 0) as PostsInTopTag,
    coalesce(ut.TotalScore, 0) as ScoreInTopTag,
    string_agg(distinct rth.TagName, ', ') as SampleTags
from UserActivity ua
left join AnswerStats asn on asn.QuestionId = ua.UserId
left join CloseReasonStats crs on crs.PostId in (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1
)
left join PostCommentsAgg pc on pc.PostId in (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId
)
left join UserTopTags ut on ut.UserId = ua.UserId
left join RecursiveTagHierarchy rth on rth.Id = (
    select min(Id) from RecursiveTagHierarchy where Id = any(
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))
        from Posts p where p.OwnerUserId = ua.UserId and p.Tags is not null limit 1
    )
)
where ua.UserRank <= 100
group by ua.UserRank, ua.DisplayName, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.TotalVotesReceived, asn.AnswerCount, asn.AvgAnswerScore, asn.MaxAnswerScore, asn.HighScoreAnswers, crs.CloseReason, crs.CloseCount, pc.CommentCount, pc.LastCommentDate, pc.Commenters, ut.Tag, ut.PostsWithTag, ut.TotalScore
order by ua.UserRank;