-- {"query": "2367.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1705} 
with RecursiveRecentBadges as (
    select 
        b.Id,
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        u.DisplayName,
        dense_rank() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b 
    join Users u on b.UserId = u.Id
    where b.Date > current_date - interval '1 year'
),
TopUsers as (
    select 
        u.Id, u.DisplayName, u.Reputation,
        coalesce(badges_count,0) as RecentBadgeCount,
        coalesce(q.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(a.AvgAnswerScore,0) as AvgAnswerScore
    from Users u
    left join (
        select UserId, count(*) as badges_count
        from RecursiveRecentBadges
        where BadgeRank <= 5
        group by UserId
    ) rrb on u.Id = rrb.UserId
    left join (
        select OwnerUserId, avg(Score) as AvgQuestionScore
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) q on u.Id = q.OwnerUserId
    left join (
        select OwnerUserId, avg(Score) as AvgAnswerScore
        from Posts 
        where PostTypeId = 2
        group by OwnerUserId
    ) a on u.Id = a.OwnerUserId
    where u.Reputation > 1000
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(distinct a.Id) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn,
        coalesce(pl.LinkCnt, 0) as LinkedPostsCount
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    left join (
        select PostId, count(*) as LinkCnt
        from PostLinks
        where LinkTypeId = 1
        group by PostId
    ) pl on p.Id = pl.PostId
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '2 years'
    group by p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.Tags, pl.LinkCnt
),
TopQuestions as (
    select *
    from QuestionStats
    where rn <= 3
),
UserActivity as (
    select 
        u.Id as UserId,
        coalesce(pq.QuestionCount,0) as QuestionsPosted,
        coalesce(pa.AnswerCount,0) as AnswersPosted,
        coalesce(cmt.CommentCount,0) as CommentsMade,
        coalesce(vt.VotesCast,0) as VotesCast,
        (select count(distinct b1.Id) from Badges b1 where b1.UserId = u.Id and b1.Class=1) as GoldBadges,
        (select count(distinct b2.Id) from Badges b2 where b2.UserId = u.Id and b2.Class=2) as SilverBadges,
        (select count(distinct b3.Id) from Badges b3 where b3.UserId = u.Id and b3.Class=3) as BronzeBadges
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts where PostTypeId=1
        group by OwnerUserId
    ) pq on u.Id = pq.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts where PostTypeId=2
        group by OwnerUserId
    ) pa on u.Id = pa.OwnerUserId
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        group by UserId
    ) cmt on u.Id = cmt.UserId
    left join (
        select UserId, count(*) as VotesCast
        from Votes
        group by UserId
    ) vt on u.Id = vt.UserId
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, p.Title as OriginalTitle, rp.Title as DuplicateTitle
    from PostLinks pl
    join Posts p on pl.PostId = p.Id
    join Posts rp on pl.RelatedPostId = rp.Id
    where pl.LinkTypeId = 3
),
RecentEditsCTE as (
    select 
        ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.UserDisplayName,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.CreationDate > current_date - interval '90 days'
),
LatestEdits as (
    select PostId, PostHistoryTypeId, CreationDate, UserId, UserDisplayName
    from RecentEditsCTE
    where rn = 1
),
CompositeResults as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        tu.RecentBadgeCount,
        qs.QuestionId,
        qs.Title as QuestionTitle,
        qs.Score as QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.VotesCast,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        le.CreationDate as LastEditDate,
        le.UserDisplayName as LastEditor,
        dup.OriginalTitle as DuplicateOriginalQuestion,
        dup.DuplicateTitle as DuplicateLinkedQuestion,
        -- Complex string manipulation: Extract first tag from Tags string
        substring(qs.Tags from '<([^<>]+)>') as FirstTag,
        -- Calculation of score/view with NULL-safe division and avoiding division by zero
        case when qs.ViewCount > 0 then round(cast(qs.Score as numeric)/qs.ViewCount, 4) else null end as ScorePerView,
        -- Conditional expression with NULL logic
        case 
            when ua.GoldBadges > 0 then 'Gold Contributor'
            when ua.SilverBadges > 5 then 'Silver Contributor'
            when ua.BronzeBadges > 10 then 'Bronze Contributor'
            else 'New Contributor'
        end as ContributorLevel,
        -- Window function ranking users by reputation within their 'ContributorLevel'
        rank() over (
            partition by
                case 
                    when ua.GoldBadges > 0 then 'Gold Contributor'
                    when ua.SilverBadges > 5 then 'Silver Contributor'
                    when ua.BronzeBadges > 10 then 'Bronze Contributor'
                    else 'New Contributor'
                end
            order by u.Reputation desc
        ) as ReputationRank
    from TopUsers u
    left join TopQuestions qs on u.Id = qs.OwnerUserId
    left join UserActivity ua on ua.UserId = u.Id
    left join LatestEdits le on le.PostId = qs.QuestionId
    left join DuplicateLinks dup on dup.PostId = qs.QuestionId
)
select * from CompositeResults
where (ContributorLevel = 'Gold Contributor' and ReputationRank <= 5)
   or (ContributorLevel = 'Silver Contributor' and ReputationRank <= 3)
order by ContributorLevel desc, ReputationRank, QuestionScore desc;