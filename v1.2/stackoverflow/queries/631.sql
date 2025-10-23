-- {"query": "631.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1411} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Date > u.CreationDate
),
TopBadges as (
    select
        UserId,
        DisplayName,
        BadgeName,
        Class,
        Date
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostStats as (
    select
        p.OwnerUserId as UserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedCount,
        max(p.ViewCount) as MaxViews,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId, p.PostTypeId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(psq.PostCount,0) as QuestionCount,
        coalesce(psq.AvgScore,0) as AvgQuestionScore,
        coalesce(psa.PostCount,0) as AnswerCount,
        coalesce(psa.AvgScore,0) as AvgAnswerScore,
        coalesce(psq.HasClosedPosts,false) or coalesce(psa.HasClosedPosts,false) as HasClosedPosts,
        coalesce(psq.AcceptedCount,0) as AcceptedQuestions
    from Users u
    left join PostStats psq on psq.UserId = u.Id and psq.PostTypeId = 1
    left join PostStats psa on psa.UserId = u.Id and psa.PostTypeId = 2
),
UserCommentsCount as (
    select
        c.UserId,
        count(*) as CommentCount
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserVotesGiven as (
    select
        v.UserId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(*) filter (where v.VoteTypeId = 3) as DownVotesGiven
    from Votes v
    where v.UserId is not null
    group by v.UserId
),
UserSummary as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.QuestionCount,
        ua.AvgQuestionScore,
        ua.AnswerCount,
        ua.AvgAnswerScore,
        ua.HasClosedPosts,
        ua.AcceptedQuestions,
        coalesce(uc.CommentCount,0) as CommentCount,
        coalesce(uv.UpVotesGiven,0) as UpVotesGiven,
        coalesce(uv.DownVotesGiven,0) as DownVotesGiven
    from UserActivity ua
    left join UserCommentsCount uc on uc.UserId = ua.Id
    left join UserVotesGiven uv on uv.UserId = ua.Id
),
PostTagExplode as (
    select
        p.Id as PostId,
        trim(both '<>' from unnest(string_to_array(p.Tags, '><'))) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagStats as (
    select
        t.TagName,
        count(distinct p.Id) as QuestionCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViews,
        count(distinct p.OwnerUserId) as DistinctUsers
    from Tags t
    left join PostTagExplode pte on pte.Tag = t.TagName
    left join Posts p on p.Id = pte.PostId
    group by t.TagName
),
TopTags as (
    select
        TagName,
        QuestionCount,
        AvgScore,
        MaxViews,
        DistinctUsers,
        row_number() over (order by QuestionCount desc) as RankByCount
    from TagStats
    where QuestionCount > 50
),
UserTopTags as (
    select
        us.Id as UserId,
        us.DisplayName,
        tt.TagName,
        ts.QuestionCount,
        ts.AvgScore
    from UserSummary us
    join PostTagExplode pte on pte.PostId in (
        select Id from Posts where OwnerUserId = us.Id and PostTypeId = 1
    )
    join Tags t on t.TagName = pte.Tag
    join TagStats ts on ts.TagName = t.TagName
    join TopTags tt on tt.TagName = ts.TagName
),
UserRankings as (
    select
        us.*,
        ntile(10) over (order by us.Reputation desc) as ReputationDecile,
        ntile(10) over (order by us.QuestionCount desc) as QuestionCountDecile,
        ntile(10) over (order by us.AnswerCount desc) as AnswerCountDecile
    from UserSummary us
)
select
    ur.Id as UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.ReputationDecile,
    ur.QuestionCount,
    ur.QuestionCountDecile,
    ur.AnswerCount,
    ur.AnswerCountDecile,
    ur.AvgQuestionScore,
    ur.AvgAnswerScore,
    ur.HasClosedPosts,
    ur.AcceptedQuestions,
    ur.CommentCount,
    ur.UpVotesGiven,
    ur.DownVotesGiven,
    coalesce(tb.BadgeName, 'No Badge') as TopBadge,
    coalesce(utt.TagName, 'No Top Tag') as FavoriteTag,
    ts.QuestionCount as TagQuestionCount,
    ts.AvgScore as TagAvgScore
from UserRankings ur
left join TopBadges tb on tb.UserId = ur.Id and tb.Date = (
    select max(Date) from TopBadges where UserId = ur.Id
)
left join (
    select
        UserId,
        TagName,
        row_number() over (partition by UserId order by QuestionCount desc) as TagRank
    from UserTopTags
) utt on utt.UserId = ur.Id and utt.TagRank = 1
left join TagStats ts on ts.TagName = utt.TagName
where ur.Reputation > 1000
order by ur.Reputation desc, ur.QuestionCount desc
limit 100;