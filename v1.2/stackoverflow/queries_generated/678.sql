-- {"query": "678.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1481} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date >= current_date - interval '365 days'
),
TopUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesCount,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesCount,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as ClosedPostsCount,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Votes v on p.Id = v.PostId
    left join PostHistory ph on p.Id = ph.PostId
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(distinct p.Id) filter (where p.PostTypeId = 1) > 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by u.Id order by p.CreationDate) as PrevPostScore,
        lead(p.Score) over (partition by u.Id order by p.CreationDate) as NextPostScore
    from Users u
    inner join Posts p on u.Id = p.OwnerUserId
    where p.CreationDate >= current_date - interval '90 days'
),
FilteredPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName as OwnerName,
        case 
            when p.ClosedDate is not null then 'Closed' 
            when p.AcceptedAnswerId is not null then 'Accepted'
            else 'Open'
        end as PostStatus,
        array_to_string(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), ', ') as ParsedTags
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 5
),
DuplicateQuestions as (
    select distinct pl.PostId as QuestionId, pl.RelatedPostId as DuplicateOfId
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select
        fp.Id,
        fp.Title,
        fp.ParsedTags,
        fp.Score,
        fp.ViewCount,
        fp.AnswerCount,
        fp.FavoriteCount,
        fp.PostStatus,
        dup.DuplicateOfId,
        dupp.Title as DuplicateOfTitle
    from FilteredPosts fp
    left join DuplicateQuestions dup on fp.Id = dup.QuestionId
    left join Posts dupp on dup.DuplicateOfId = dupp.Id
),
RecentClosedQuestions as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title as QuestionTitle,
        u.DisplayName as CloserName
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    inner join CloseReasonTypes crt on ph.Comment::int = crt.Id
    inner join Posts p on ph.PostId = p.Id
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId = 10
      and ph.CreationDate >= current_date - interval '180 days'
),
UserBadgesRanked as (
    select 
        UserId,
        BadgeName,
        Class,
        BadgeRank
    from RecursiveUserBadges
    where BadgeRank <= 3
),
UserSummary as (
    select 
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.UpVotesCount,
        tu.DownVotesCount,
        tu.QuestionsCount,
        tu.AnswersCount,
        tu.ClosedPostsCount,
        tu.DuplicateLinksCount,
        coalesce(ub.BadgeCountGold,0) as GoldBadges,
        coalesce(ub.BadgeCountSilver,0) as SilverBadges,
        coalesce(ub.BadgeCountBronze,0) as BronzeBadges
    from TopUsers tu
    left join (
        select 
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as BadgeCountGold,
            sum(case when Class = 2 then 1 else 0 end) as BadgeCountSilver,
            sum(case when Class = 3 then 1 else 0 end) as BadgeCountBronze
        from Badges
        group by UserId
    ) ub on tu.Id = ub.UserId
)
select 
    us.DisplayName as User,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionsCount,
    us.AnswersCount,
    us.ClosedPostsCount,
    us.DuplicateLinksCount,
    qwd.Title as QuestionTitle,
    qwd.Score as QuestionScore,
    qwd.ViewCount as QuestionViews,
    qwd.AnswerCount as QuestionAnswers,
    qwd.FavoriteCount as QuestionFavorites,
    qwd.PostStatus,
    qwd.ParsedTags,
    qwd.DuplicateOfTitle,
    rcq.CloseDate,
    rcq.CloseReason,
    rcq.CloserName
from UserSummary us
left join FilteredPosts fp on fp.OwnerName = us.DisplayName
left join QuestionsWithDuplicates qwd on qwd.Id = fp.Id
left join RecentClosedQuestions rcq on rcq.PostId = fp.Id
where us.Reputation > 1000
  and (qwd.PostStatus = 'Open' or qwd.PostStatus is null)
order by us.Reputation desc, qwd.Score desc
limit 100;