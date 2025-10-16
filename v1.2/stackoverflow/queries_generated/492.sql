-- {"query": "492.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1647} 
with RecursiveTagHierarchy as (
    select 
        t.Id, 
        t.TagName, 
        t.Count,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        t.Id, 
        t.TagName, 
        t.Count,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.Count > 50 and r.Level < 2
),
UserBadgeCounts as (
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
PostScoreStats as (
    select 
        p.OwnerUserId,
        count(*) as TotalPosts,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as Questions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as Answers,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedAnswersCount
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopActiveUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        pss.TotalPosts,
        pss.AvgScore,
        pss.MaxScore,
        pss.MinScore,
        pss.Questions,
        pss.Answers,
        pss.AcceptedAnswersCount,
        row_number() over (order by pss.TotalPosts desc, u.Reputation desc) as UserRank
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join PostScoreStats pss on pss.OwnerUserId = u.Id
    where u.Reputation > 1000
),
LatestPostEdits as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        max(ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastContentEditId,
        max(ph.Id) filter (where ph.PostHistoryTypeId = 10) as LastCloseVoteId
    from PostHistory ph
    group by ph.PostId
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as SelfAnsweredCount,
        bool_or(a.AcceptedAnswerId = a.Id) as HasAcceptedAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId
),
UserCommentActivity as (
    select 
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
UserPostVoteSummary as (
    select 
        p.OwnerUserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        sum(coalesce(v.BountyAmount,0)) as TotalBountyReceived
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.OwnerUserId is not null
    group by p.OwnerUserId
)
select 
    u.UserRank,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TagBasedBadges,
    u.TotalPosts,
    u.AvgScore,
    u.MaxScore,
    u.MinScore,
    u.Questions,
    u.Answers,
    u.AcceptedAnswersCount,
    coalesce(uc.CommentCount,0) as CommentCount,
    coalesce(uc.AvgCommentLength,0) as AvgCommentLength,
    coalesce(uc.LastCommentDate, null) as LastCommentDate,
    coalesce(uv.UpVotes,0) as UpVotes,
    coalesce(uv.DownVotes,0) as DownVotes,
    coalesce(uv.FavoriteVotes,0) as FavoriteVotes,
    coalesce(uv.TotalBountyReceived,0) as TotalBountyReceived,
    qa.QuestionId,
    qa.Title,
    qa.QuestionCreation,
    qa.QuestionScore,
    qa.ViewCount,
    qa.Tags,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.MaxAnswerScore,
    qa.SelfAnsweredCount,
    qa.HasAcceptedAnswer,
    string_agg(distinct rth.TagName, ', ') as RelatedTags
from TopActiveUsers u
left join UserCommentActivity uc on uc.UserId = u.Id
left join UserPostVoteSummary uv on uv.OwnerUserId = u.Id
left join QuestionAnswerStats qa on qa.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.Score desc limit 1
)
left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(qa.Tags, '')) > 0
where u.UserRank <= 50
group by 
    u.UserRank, u.DisplayName, u.Reputation, u.Location, u.GoldBadges, u.SilverBadges, u.BronzeBadges, u.TagBasedBadges,
    u.TotalPosts, u.AvgScore, u.MaxScore, u.MinScore, u.Questions, u.Answers, u.AcceptedAnswersCount,
    uc.CommentCount, uc.AvgCommentLength, uc.LastCommentDate,
    uv.UpVotes, uv.DownVotes, uv.FavoriteVotes, uv.TotalBountyReceived,
    qa.QuestionId, qa.Title, qa.QuestionCreation, qa.QuestionScore, qa.ViewCount, qa.Tags, qa.AnswerCount, qa.AvgAnswerScore, qa.MaxAnswerScore, qa.SelfAnsweredCount, qa.HasAcceptedAnswer
order by u.UserRank;