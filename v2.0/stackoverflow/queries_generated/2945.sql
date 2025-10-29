-- {"query": "2945.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1530} 
with RecursivePostVotes as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as RankByUser
    from
        Posts p
        left join (
            select
                PostId,
                sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
                sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
            from Votes
            group by PostId
        ) v on p.Id = v.PostId
    where p.PostTypeId in (1, 2) -- Questions or Answers
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           coalesce(b.BadgeCount, 0) as BadgeCount,
           coalesce(q.QuestionCount, 0) as QuestionCount,
           coalesce(a.AnswerCount, 0) as AnswerCount
    from Users u
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) q on u.Id = q.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) a on u.Id = a.OwnerUserId
    where u.Reputation > 1000
),
TaggedQuestions as (
    select 
        p.Id, p.OwnerUserId, p.Title, p.Tags, p.CreationDate,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags != ''
),
DuplicatePostLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
RankedAnswers as (
    select 
        p.*,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where PostTypeId = 2 and p.ParentId is not null
),
RecentEdits as (
    select ph.PostId, ph.UserId, ph.PostHistoryTypeId, ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRankDesc
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
FilteredRecentEdits as (
    select re.*
    from RecentEdits re
    where re.EditRankDesc = 1
),
UserEngagement as (
    select 
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        count(distinct q.Id) as TotalQuestions,
        count(distinct a.Id) as TotalAnswers,
        count(distinct v.Id) as TotalVotes,
        count(distinct c.Id) as TotalComments,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id
)
select 
    tu.DisplayName as UserName,
    tu.Reputation,
    tu.BadgeCount,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalVotes,
    ue.TotalComments,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    pq.Tag,
    count(distinct pq.Id) as TagQuestionCount,
    coalesce(avg(pv.Score),0) as AvgPostScore,
    coalesce(max(pv.Score),0) as MaxPostScore,
    coalesce(min(pv.Score),0) as MinPostScore,
    coalesce(sum(pv.UpVotes),0) as TotalUpVotes,
    coalesce(sum(pv.DownVotes),0) as TotalDownVotes,
    case 
        when coalesce(sum(pv.DownVotes),0) = 0 then null
        else round(cast(sum(pv.UpVotes) as numeric)/nullif(sum(pv.DownVotes),0),2)
    end as UpDownRatio,
    (select string_agg(distinct lt.Name, ', ' order by lt.Name)
     from PostLinks pl
     join LinkTypes lt on pl.LinkTypeId = lt.Id
     join Posts p2 on p2.Id = pl.PostId
     where p2.OwnerUserId = tu.Id
    ) as LinkTypesInPosts,
    (select count(*) from DuplicatePostLinks dpl where dpl.PostId in (select Id from Posts where OwnerUserId=tu.Id)) as DuplicatePostCount,
    (select string_agg(distinct concat_ws(': ', ph.Name, count(ph.Id)), ', ')
     from PostHistory phh
     join PostHistoryTypes ph on ph.Id = phh.PostHistoryTypeId
     where phh.PostId in (select Id from Posts where OwnerUserId=tu.Id)
     group by ph.Name
    ) as PostHistorySummary,
    (select count(*) from FilteredRecentEdits fre where fre.UserId = tu.Id) as RecentEditCount
from TopUsers tu
left join UserEngagement ue on ue.UserId = tu.Id
left join Posts p on p.OwnerUserId = tu.Id
left join RecursivePostVotes pv on pv.PostId = p.Id
left join TaggedQuestions pq on pq.OwnerUserId = tu.Id
where pq.Tag is not null
group by 
    tu.Id, tu.DisplayName, tu.Reputation, tu.BadgeCount, 
    ue.TotalPosts, ue.TotalQuestions, ue.TotalAnswers, ue.TotalVotes, ue.TotalComments, ue.GoldBadges, ue.SilverBadges, ue.BronzeBadges
order by AvgPostScore desc, TagQuestionCount desc
limit 100;