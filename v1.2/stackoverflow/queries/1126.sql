-- {"query": "1126.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1906} 
with RecursiveUserActivity as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate,
           coalesce(u.WebsiteUrl, 'N/A') as WebsiteUrlNormalized,
           u.Location,
           row_number() over (partition by u.Id order by u.CreationDate) as ActivityRank,
           count(p.Id) over (partition by u.Id) as PostCount,
           count(c.Id) over (partition by u.Id) as CommentCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    where u.Reputation > 1000
),
LatestUserBadge as (
    select b.UserId,
           max(b.Date) as LastBadgeDate,
           string_agg(distinct b.Name, ', ') filter (where b.Class = 1) as GoldBadges,
           string_agg(distinct b.Name, ', ') filter (where b.Class = 2) as SilverBadges,
           string_agg(distinct b.Name, ', ') filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
TopTags as (
    select regexp_split_to_table(
             substring(p.Tags, 2, length(p.Tags) - 2), '><') as TagName,
           p.OwnerUserId,
           count(*) as TagUsageCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by TagName, p.OwnerUserId
),
UserTopTagRanked as (
    select tt.OwnerUserId as UserId,
           tt.TagName,
           tt.TagUsageCount,
           rank() over (partition by tt.OwnerUserId order by tt.TagUsageCount desc) as TagRank
    from TopTags tt
),
UserRecentActivityPosts as (
    select p.Id as PostId,
           p.OwnerUserId as UserId,
           p.PostTypeId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.FavoriteCount,
           p.LastActivityDate,
           p.ClosedDate,
           p.Title,
           lower(coalesce(p.OwnerDisplayName, '')) as OwnerDisplayNameNormalized,
           p.Tags
    from Posts p
    where p.CreationDate > cast('2024-10-01' as date) - interval '90 days'
),
UserPostStats as (
    select ra.UserId,
           count(case when ra.PostTypeId = 1 then 1 end) as RecentQuestions,
           count(case when ra.PostTypeId = 2 then 1 end) as RecentAnswers,
           avg(ra.Score) filter (where ra.PostTypeId in (1,2)) as AvgScoreRecentPosts,
           max(ra.Score) filter (where ra.PostTypeId in (1,2)) as MaxScoreRecentPost,
           count(*) as TotalRecentPosts
    from UserRecentActivityPosts ra
    group by ra.UserId
),
UserClosedQuestions as (
    select p.OwnerUserId as UserId,
           count(*) as ClosedQuestionCount,
           count(p.Id) filter (where p.ClosedDate is not null and p.ClosedDate >= cast('2024-10-01' as date) - interval '1 year') as ClosedLastYear
    from Posts p
    where p.PostTypeId = 1
    group by p.OwnerUserId
),
QuestionsWithAnswers as (
    select q.Id as QuestionId,
           q.OwnerUserId as QuestionOwnerId,
           q.Title,
           q.Tags,
           q.CreationDate as QuestionCreation,
           a.Id as AnswerId,
           a.OwnerUserId as AnswerOwnerId,
           a.CreationDate as AnswerCreation,
           a.Score as AnswerScore,
           a.AcceptedAnswerId,
           u.DisplayName as AnswerUserName,
           row_number() over (partition by q.Id order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
QuestionWithBestAnswer as (
    select qa.QuestionId,
           qa.QuestionOwnerId,
           qa.Title,
           qa.Tags,
           qa.QuestionCreation,
           qa.AnswerId,
           qa.AnswerOwnerId,
           qa.AnswerCreation,
           qa.AnswerScore,
           qa.AnswerUserName
    from QuestionsWithAnswers qa
    where qa.AnswerRank = 1
),
UserVoteSummary as (
    select v.UserId,
           count(*) filter (where vt.Name = 'UpMod') as UpVotesGiven,
           count(*) filter (where vt.Name = 'DownMod') as DownVotesGiven,
           count(*) filter (where vt.Name = 'AcceptedByOriginator') as AcceptedVotesGiven,
           count(distinct v.PostId) as UniquePostsVoted
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
DuplicatePostsWithOrigin as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate,
           po.OwnerUserId as PostOwnerUserId,
           pr.OwnerUserId as RelatedPostOwnerUserId,
           pl.Id as LinkId
    from PostLinks pl
    left join Posts po on po.Id = pl.PostId
    left join Posts pr on pr.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
DuplicatePostsCount as (
    select PostOwnerUserId,
           count(*) as DuplicatePostsMade
    from DuplicatePostsWithOrigin
    group by PostOwnerUserId
),
FinalUserStats as (
    select ua.UserId,
           ua.DisplayName,
           ua.Reputation,
           ua.CreationDate,
           ua.LastAccessDate,
           ua.WebsiteUrlNormalized,
           ua.Location,
           ua.ActivityRank,
           ua.PostCount,
           ua.CommentCount,
           lub.GoldBadges,
           lub.SilverBadges,
           lub.BronzeBadges,
           uttr.TagName as TopTag,
           uttr.TagUsageCount as TopTagUsage,
           ups.RecentQuestions,
           ups.RecentAnswers,
           ups.AvgScoreRecentPosts,
           ups.MaxScoreRecentPost,
           ucq.ClosedQuestionCount,
           ucq.ClosedLastYear,
           uvs.UpVotesGiven,
           uvs.DownVotesGiven,
           uvs.AcceptedVotesGiven,
           coalesce(dpc.DuplicatePostsMade,0) as DuplicatePostsMade
    from RecursiveUserActivity ua
    left join LatestUserBadge lub on lub.UserId = ua.UserId
    left join UserTopTagRanked uttr on uttr.UserId = ua.UserId and uttr.TagRank = 1
    left join UserPostStats ups on ups.UserId = ua.UserId
    left join UserClosedQuestions ucq on ucq.UserId = ua.UserId
    left join UserVoteSummary uvs on uvs.UserId = ua.UserId
    left join DuplicatePostsCount dpc on dpc.PostOwnerUserId = ua.UserId
    where ua.ActivityRank = 1
)
select fus.UserId,
       fus.DisplayName,
       fus.Reputation,
       fus.PostCount,
       fus.CommentCount,
       fus.GoldBadges,
       fus.SilverBadges,
       fus.BronzeBadges,
       fus.TopTag,
       fus.TopTagUsage,
       fus.RecentQuestions,
       fus.RecentAnswers,
       round(coalesce(fus.AvgScoreRecentPosts,0)::numeric,2) as AvgScoreRecentPosts,
       fus.MaxScoreRecentPost,
       fus.ClosedQuestionCount,
       fus.ClosedLastYear,
       fus.UpVotesGiven,
       fus.DownVotesGiven,
       fus.AcceptedVotesGiven,
       fus.DuplicatePostsMade,
       -- Aggregate text of top 3 recent questions titles containing tag 'sql' (case insensitive)
       coalesce((
           select string_agg(distinct left(q.Title, 50), ' | ')
           from Posts q
           where q.OwnerUserId = fus.UserId
             and q.PostTypeId = 1
             and q.CreationDate > cast('2024-10-01' as date) - interval '30 days'
             and (q.Title ilike '%sql%' or (q.Tags is not null and q.Tags ilike '%sql%'))
           limit 3
       ), '') as TopRecentSQLQuestionTitles,
       -- Count of Answers accepted as best answer by others in last year
       (select count(*)
        from Posts a
        join Posts q on q.AcceptedAnswerId = a.Id and a.OwnerUserId = fus.UserId and q.CreationDate >= cast('2024-10-01' as date) - interval '1 year'
        where a.PostTypeId = 2) as AcceptedAnswersLastYear
from FinalUserStats fus
order by fus.Reputation desc nulls last, fus.PostCount desc
limit 50;